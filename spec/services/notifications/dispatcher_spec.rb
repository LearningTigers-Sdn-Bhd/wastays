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
end
