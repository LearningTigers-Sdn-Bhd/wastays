require "rails_helper"

RSpec.describe Notifications::Dispatcher do
  include ActiveJob::TestHelper

  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: Time.zone.local(2026, 5, 8, 15, 0)) }

  before do
    ActiveJob::Base.queue_adapter = :test
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
    booking.update!(status: "completed", checked_out_at: Time.zone.local(2026, 5, 8, 16, 0))

    expect {
      described_class.new(event: :booking_completed, booking: booking).call
    }.to change(NotificationDelivery, :count).by(1)
      .and have_enqueued_job(Notifications::DeliverJob).exactly(1).times
  end

  it "schedules pre-arrival deliveries for d2 and d1 across both channels" do
    NotificationConfig.create!(
      hotel: hotel,
      notification_type: "pre_arrival_notification",
      enabled: true,
      channels: %w[whatsapp email],
      settings: { "stages" => %w[d2 d1] }
    )
    booking.update!(status: "confirmed", check_in: Date.current + 5.days, check_out: Date.current + 6.days)

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
    booking.update!(status: "confirmed", check_in: Date.current + 5.days, check_out: Date.current + 6.days)

    described_class.new(event: :booking_confirmed, booking: booking).call
    delivery = NotificationDelivery.where(booking: booking, notification_type: "pre_arrival_notification", status: "pending").first
    old_scheduled_for = delivery.payload["scheduled_for"] || delivery.payload[:scheduled_for]
    booking.update!(check_in: booking.check_in + 1.day, check_out: booking.check_out + 1.day)

    described_class.new(event: :booking_updated, booking: booking).call

    expect(delivery.reload.payload["scheduled_for"]).not_to eq(old_scheduled_for)
    expect(delivery.trigger_event).to eq("booking_updated")
  end
end
