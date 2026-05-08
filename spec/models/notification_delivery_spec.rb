require "rails_helper"

RSpec.describe NotificationDelivery, type: :model do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "confirmed") }

  it "is valid with supported status and channel" do
    delivery = described_class.new(
      hotel: hotel,
      booking: booking,
      notification_type: "check_in_confirmation",
      channel: "whatsapp",
      trigger_event: "booking_checked_in",
      status: "pending",
      idempotency_key: "#{hotel.id}:#{booking.id}:check_in_confirmation:whatsapp:booking_checked_in",
      payload: { guest_name: booking.guest_name }
    )

    expect(delivery).to be_valid
  end

  it "enforces idempotency key uniqueness" do
    key = "#{hotel.id}:#{booking.id}:check_in_confirmation:email:booking_checked_in"

    described_class.create!(
      hotel: hotel,
      booking: booking,
      notification_type: "check_in_confirmation",
      channel: "email",
      trigger_event: "booking_checked_in",
      status: "pending",
      idempotency_key: key,
      payload: {}
    )

    duplicate = described_class.new(
      hotel: hotel,
      booking: booking,
      notification_type: "check_in_confirmation",
      channel: "email",
      trigger_event: "booking_checked_in",
      status: "pending",
      idempotency_key: key,
      payload: {}
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:idempotency_key]).to include("has already been taken")
  end
end
