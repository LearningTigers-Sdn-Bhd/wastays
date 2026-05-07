require "rails_helper"

RSpec.describe AiConciergeV3::Tools::HotelInformation::GetBookingContextTool do
  it "returns structured booking rows for a matching phone" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel: hotel, name: "Executive Penthouse")
    booking = create(:booking,
      hotel: hotel,
      guest_phone: "+60123456789",
      status: "checked_in",
      check_in: Date.new(2026, 5, 21),
      check_out: Date.new(2026, 5, 23)
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    result = described_class.new(hotel: hotel, phone: "+60123456789").call

    expect(result).to eq(
      "bookings" => [
        {
          "date_range" => "May 21 - May 23",
          "room_type_name" => "Executive Penthouse"
        }
      ]
    )
  end

  it "returns an empty bookings list when no active booking is found" do
    hotel = create(:hotel)

    result = described_class.new(hotel: hotel, phone: "+60123456789").call

    expect(result).to eq("bookings" => [])
  end
end
