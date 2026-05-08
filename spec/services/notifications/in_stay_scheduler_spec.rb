require "rails_helper"

RSpec.describe Notifications::InStayScheduler do
  include ActiveJob::TestHelper

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
end
