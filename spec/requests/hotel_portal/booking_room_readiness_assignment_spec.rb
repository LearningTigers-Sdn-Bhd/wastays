# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking room readiness assignment", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ], quantity: 1) }

  before do
    role = create(:role, account: hotel.account)
    permission = Permission.find_by(slug: "manage_bookings") || Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings', name: 'Manage Bookings')
    role.permissions << permission
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "blocks assigning a pending_cleaning room when updating a booking" do
    booking = create(:booking, hotel: hotel, status: "confirmed")
    booking_room = create(:booking_room, booking: booking, room_type: room_type, room_number: nil, quantity: 1, subtotal: 200)
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")

    patch hotel_booking_path(hotel, booking), params: {
      booking: {
        booking_rooms_attributes: {
          "0" => { id: booking_room.id, room_number: "101" }
        }
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(booking_room.reload.room_number).to be_nil
  end
end
