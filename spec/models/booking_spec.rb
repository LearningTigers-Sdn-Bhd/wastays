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

  describe "CTA/CTD validations" do
    let(:hotel) { create(:hotel) }
    let(:room_type) { create(:room_type, hotel: hotel) }
    let(:check_in) { Date.current }
    let(:check_out) { check_in + 2.days }

    it "allows booking when there are no restrictions" do
      booking = build(:booking, hotel: hotel, check_in: check_in, check_out: check_out)
      booking.booking_rooms.build(room_type: room_type, subtotal: 100.0)

      expect(booking).to be_valid
    end

    it "blocks booking when check-in date is CTA" do
      RoomRate.create!(room_type: room_type, date: check_in, price: 100, currency: "MYR", rate_plan: room_type.rate_plans.first, closed_to_arrival: true)

      booking = build(:booking, hotel: hotel, check_in: check_in, check_out: check_out)
      booking.booking_rooms.build(room_type: room_type, subtotal: 100.0)

      expect(booking).not_to be_valid
      expect(booking.errors[:check_in].first).to include("closed to arrival")
    end

    it "blocks booking when check-out date is CTD" do
      RoomRate.create!(room_type: room_type, date: check_out, price: 100, currency: "MYR", rate_plan: room_type.rate_plans.first, closed_to_departure: true)

      booking = build(:booking, hotel: hotel, check_in: check_in, check_out: check_out)
      booking.booking_rooms.build(room_type: room_type, subtotal: 100.0)

      expect(booking).not_to be_valid
      expect(booking.errors[:check_out].first).to include("closed to departure")
    end

    it "does not affect existing bookings when restrictions are added later" do
      booking = create(:booking, hotel: hotel, check_in: check_in, check_out: check_out)
      create(:booking_room, booking: booking, room_type: room_type)

      RoomRate.create!(room_type: room_type, date: check_in, price: 100, currency: "MYR", rate_plan: room_type.rate_plans.first, closed_to_arrival: true)

      expect(booking.reload).to be_valid
    end
  end
end
