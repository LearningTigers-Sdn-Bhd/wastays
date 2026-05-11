require "rails_helper"

RSpec.describe Notifications::PayloadBuilders::CheckInConfirmation do
  it "builds the normalized payload from the booking" do
    booking = create(:booking, status: "checked_in", checked_in_at: Time.zone.local(2026, 5, 8, 15, 0))

    payload = described_class.new(booking: booking).call

    expect(payload[:notification_type]).to eq("check_in_confirmation")
    expect(payload[:guest_name]).to eq(booking.guest_name)
    expect(payload[:hotel_name]).to eq(booking.hotel.name)
    expect(payload[:checked_in_at]).to eq(booking.checked_in_at.iso8601)
  end
end
