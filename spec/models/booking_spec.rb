require "rails_helper"

RSpec.describe Booking, type: :model do
  describe "fund_collector normalization" do
    it "normalizes an invalid legacy fund_collector during validation" do
      booking = build(:booking, fund_collector: "legacy_value", booking_quote: nil, source: "channel_manager")

      booking.validate

      expect(booking.fund_collector).to eq("unknown")
    end

    it "infers hotel when an invalid legacy value exists on a walk-in booking" do
      booking = build(:booking, :direct_hotel_payment, fund_collector: "legacy_value")

      booking.validate

      expect(booking.fund_collector).to eq("hotel")
    end
  end
end
