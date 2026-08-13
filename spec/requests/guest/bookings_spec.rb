require "rails_helper"

RSpec.describe "Guest::Bookings DND toggle", type: :request do
  let(:guest) { create(:guest, phone: "+60123456789") }
  let(:hotel) { create(:hotel, status: "live") }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Standard Room") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "checked_in",
      guest_name: guest.name,
      guest_email: guest.email,
      guest_phone: guest.phone,
      check_in: Date.current,
      check_out: Date.current + 2.days
    )
  end
  let!(:booking_room) do
    create(:booking_room,
      booking: booking,
      room_type: room_type,
      subtotal: 100.0,
      room_number: "101"
    )
  end

  before do
    create(:booking_guest, guest: guest, booking: booking, is_primary: true)
    sign_in_guest!(guest)
  end

  def sign_in_guest!(g)
    otp = g.generate_otp!
    post guest_login_path, params: { phone: g.phone, otp: otp }
    follow_redirect!
  end

  describe "PATCH /guest/bookings/:id/toggle_dnd" do
    it "toggles the DND flag on the assigned room status" do
      room_status = RoomStatus.find_or_create_by!(
        hotel: hotel,
        room_type: room_type,
        room_number: "101"
      )
      expect(room_status.active_dnd?).to be false

      # Toggle DND ON
      patch toggle_dnd_guest_booking_path(booking)
      expect(response).to redirect_to(guest_booking_path(booking))
      expect(flash[:notice]).to eq("Do Not Disturb preference updated successfully.")
      expect(room_status.reload.active_dnd?).to be true

      # Toggle DND OFF
      patch toggle_dnd_guest_booking_path(booking)
      expect(response).to redirect_to(guest_booking_path(booking))
      expect(flash[:notice]).to eq("Do Not Disturb preference updated successfully.")
      expect(room_status.reload.active_dnd?).to be false
    end

    it "redirects and fails if booking status is not checked_in" do
      booking.update_columns(status: "confirmed") # bypass validation

      patch toggle_dnd_guest_booking_path(booking)
      expect(response).to redirect_to(guest_booking_path(booking))
      expect(flash[:alert]).to eq("Cannot toggle Do Not Disturb if you are not currently checked in.")
    end

    it "redirects when the booking belongs to another guest" do
      other_guest = create(:guest, phone: "+60199999999")
      other_booking = create(:booking, hotel: hotel, status: "checked_in")
      create(:booking_room, booking: other_booking, room_type: room_type, room_number: "102")
      create(:booking_guest, guest: other_guest, booking: other_booking, is_primary: true)

      patch toggle_dnd_guest_booking_path(other_booking)
      expect(response).to redirect_to(guest_bookings_path)
    end
  end
end
