require "rails_helper"

RSpec.describe Notifications::InStayScheduler do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, check_in: Date.current + 5.days, check_out: Date.current + 7.days) }

  before do
    ActiveJob::Base.queue_adapter = :test
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
  end

  it "creates one pending delivery per enabled rule and channel" do
    expect {
      described_class.new(booking: booking).schedule!(trigger_event: "booking_confirmed")
    }.to change(NotificationDelivery, :count).by(6)

    expect(NotificationDelivery.where(notification_type: "in_stay_guest_messaging", status: "pending").count).to eq(6)
    expect(enqueued_jobs.count { |job| job[:job] == Notifications::DeliverJob }).to eq(6)
  end

  it "reschedules only pending deliveries" do
    scheduler = described_class.new(booking: booking)
    scheduler.schedule!(trigger_event: "booking_confirmed")
    pending_delivery = NotificationDelivery.where(notification_type: "in_stay_guest_messaging", status: "pending").first
    old_scheduled_for = pending_delivery.payload["scheduled_for"]

    booking.update!(check_in: booking.check_in + 1.day, check_out: booking.check_out + 1.day)
    scheduler.reschedule_pending!(trigger_event: "booking_updated")

    expect(pending_delivery.reload.payload["scheduled_for"]).not_to eq(old_scheduled_for)
    expect(pending_delivery.trigger_event).to eq("booking_updated")
  end

  it "rolls past in-stay times to the next valid day before check-out" do
    booking.update!(check_in: Date.current, check_out: Date.current + 2.days)

    travel_to(Time.zone.local(Date.current.year, Date.current.month, Date.current.day, 15, 0, 0)) do
      described_class.new(booking: booking).schedule!(trigger_event: "booking_confirmed")
    end

    activity_delivery = NotificationDelivery.find_by!(
      booking: booking,
      notification_type: "in_stay_guest_messaging",
      channel: "whatsapp",
      idempotency_key: "#{hotel.id}:#{booking.id}:in_stay_guest_messaging:whatsapp:activity"
    )

    expect(activity_delivery.status).to eq("pending")
    expect(Time.zone.parse(activity_delivery.payload["scheduled_for"]).to_date).to eq(Date.current + 1.day)
  end

  it "marks delivery skipped when no future in-stay slot remains before check-out" do
    booking.update!(check_in: Date.current, check_out: Date.current + 1.day)

    travel_to(Time.zone.local(Date.current.year, Date.current.month, Date.current.day, 15, 0, 0)) do
      described_class.new(booking: booking).schedule!(trigger_event: "booking_confirmed")
    end

    activity_delivery = NotificationDelivery.find_by!(
      booking: booking,
      notification_type: "in_stay_guest_messaging",
      channel: "whatsapp",
      idempotency_key: "#{hotel.id}:#{booking.id}:in_stay_guest_messaging:whatsapp:activity"
    )

    expect(activity_delivery.status).to eq("skipped")
    expect(activity_delivery.error_message).to eq("In-stay activity has no future schedule before check-out")
  end
end
