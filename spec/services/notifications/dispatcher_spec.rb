require "rails_helper"

RSpec.describe Notifications::Dispatcher do
  include ActiveJob::TestHelper

  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, plan: plan) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: Time.zone.local(2026, 5, 8, 15, 0)) }

  before do
    ActiveJob::Base.queue_adapter = :test
    %w[checkin_confirmation checkout_receipt_review automated_prearrival welcoming_instay_messaging].each do |slug|
      create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: slug), enabled: true)
    end
    NotificationConfig.create!(hotel: hotel, notification_type: "check_in_confirmation", enabled: true, channels: %w[whatsapp email], settings: {})
  end

  it "creates one delivery per enabled channel and enqueues jobs" do
    expect {
      described_class.new(event: :booking_checked_in, booking: booking).call
    }.to change(NotificationDelivery, :count).by(2)
      .and have_enqueued_job(Notifications::DeliverJob).exactly(2).times
  end

  it "does not create duplicate deliveries for the same booking event" do
    dispatcher = described_class.new(event: :booking_checked_in, booking: booking)

    dispatcher.call
    expect { dispatcher.call }.not_to change(NotificationDelivery, :count)
  end

  it "schedules post-stay review delivery on booking completion" do
    NotificationConfig.create!(
      hotel: hotel,
      notification_type: "post_stay_review_request",
      enabled: true,
      channels: %w[whatsapp],
      settings: { "review_link" => "https://g.page/r/example/review", "send_delay_hours" => 2 }
    )
    NotificationConfig.create!(
      hotel: hotel,
      notification_type: "check_out_receipt_message",
      enabled: true,
      channels: %w[email],
      settings: {}
    )
    booking.transition_status_to!("completed", event: "check_out", attributes: { checked_out_at: Time.zone.local(2026, 5, 8, 16, 0) })

    expect {
      described_class.new(event: :booking_completed, booking: booking).call
    }.to change(NotificationDelivery, :count).by(2)
      .and have_enqueued_job(Notifications::DeliverJob).exactly(2).times
  end

  it "schedules pre-arrival deliveries for d2 and d1 across both channels" do
    NotificationConfig.create!(
      hotel: hotel,
      notification_type: "pre_arrival_notification",
      enabled: true,
      channels: %w[whatsapp email],
      settings: { "stages" => %w[d2 d1] }
    )
    booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current + 5.days, check_out: Date.current + 6.days)

    expect {
      described_class.new(event: :booking_confirmed, booking: booking).call
    }.to change(NotificationDelivery, :count).by(4)

    deliver_jobs = enqueued_jobs.select { |job| job[:job] == Notifications::DeliverJob }
    expect(deliver_jobs.count).to eq(4)
  end

  it "reschedules only pending pre-arrival deliveries on booking_updated" do
    NotificationConfig.create!(
      hotel: hotel,
      notification_type: "pre_arrival_notification",
      enabled: true,
      channels: %w[whatsapp email],
      settings: { "stages" => %w[d2 d1] }
    )
    booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current + 5.days, check_out: Date.current + 6.days)

    described_class.new(event: :booking_confirmed, booking: booking).call
    delivery = NotificationDelivery.where(booking: booking, notification_type: "pre_arrival_notification", status: "pending").first
    old_scheduled_for = delivery.payload["scheduled_for"] || delivery.payload[:scheduled_for]
    booking.update!(check_in: booking.check_in + 1.day, check_out: booking.check_out + 1.day)

    described_class.new(event: :booking_updated, booking: booking).call

    expect(delivery.reload.payload["scheduled_for"]).not_to eq(old_scheduled_for)
    expect(delivery.trigger_event).to eq("booking_updated")
  end

  it "schedules in-stay deliveries on booking_confirmed when enabled" do
    NotificationConfig.create!(
      hotel: hotel,
      notification_type: "in_stay_guest_messaging",
      enabled: true,
      channels: %w[whatsapp email],
      settings: {
        "rules" => {
          "mid_stay" => { "enabled" => true, "time" => "12:00" },
          "upsell" => { "enabled" => true, "time" => "17:00" },
          "activity" => { "enabled" => true, "time" => "10:00" }
        },
        "quiet_hours" => { "enabled" => true, "start" => "22:00", "end" => "08:00" }
      }
    )
    booking = create(:booking, hotel: hotel, status: "confirmed", check_in: Date.current + 5.days, check_out: Date.current + 7.days)

    expect {
      described_class.new(event: :booking_confirmed, booking: booking).call
    }.to change { NotificationDelivery.where(notification_type: "in_stay_guest_messaging").count }.by(6)
  end
end
