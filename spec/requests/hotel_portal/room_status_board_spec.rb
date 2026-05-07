# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Room Status", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  before do
    create(:user_hotel_access, user: user, hotel: hotel)
    sign_in_as(user)
  end

  it "responds successfully for authenticated hotel staff" do
    get hotel_room_status_board_path(hotel)

    expect(response).to have_http_status(:success)
  end

  it "renders occupancy block for bookings that start before the selected board window" do
    start_date = Date.new(2026, 5, 7)
    room_type = create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ])
    booking = create(
      :booking,
      hotel: hotel,
      status: "checked_in",
      guest_name: "Carryover Guest",
      check_in: start_date - 1.day,
      check_out: start_date + 1.day
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    get hotel_room_status_board_path(hotel), params: { start_date: start_date.to_s }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Carryover Guest")
  end
end
