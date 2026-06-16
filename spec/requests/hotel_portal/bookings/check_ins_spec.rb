require "rails_helper"

RSpec.describe "HotelPortal::Bookings::CheckIns", type: :request do
  let(:hotel) { create(:hotel, tourism_tax_enabled: true, tourism_tax_amount: 10.0) }
  let(:user) { create(:user, :superadmin) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_country: "United States",
      tourism_tax_applied: true,
      tourism_tax_amount: 20.0,
      booking_quote: nil
    )
  end

  before do
    create(:booking_room, booking: booking, room_type: room_type, quantity: 1)
    sign_in_as(user)
  end

  describe "POST /create" do
    it "updates tourism_tax_collected but ignores tourism_tax_amount from params" do
      post check_in_hotel_booking_path(hotel, booking, format: :html), params: {
        booking: {
          tourism_tax_collected: "1",
          tourism_tax_amount: "50.00",
          booking_rooms_attributes: [
            { id: booking.booking_rooms.first.id, room_number: "101" }
          ]
        }
      }

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.tourism_tax_collected).to be true
      expect(booking.tourism_tax_amount).to eq(20.00) # Remains unchanged
    end

    it "can set tourism_tax_collected to false" do
      booking.update!(tourism_tax_collected: true)

      post check_in_hotel_booking_path(hotel, booking, format: :html), params: {
        booking: {
          tourism_tax_collected: "0",
          booking_rooms_attributes: [
            { id: booking.booking_rooms.first.id, room_number: "101" }
          ]
        }
      }

      expect(booking.reload.tourism_tax_collected).to be false
    end
  end
end
