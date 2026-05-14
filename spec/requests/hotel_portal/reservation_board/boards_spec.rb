# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ReservationBoard::Boards", type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ]) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def sign_in_with_permissions(*slugs)
    user = create(:user)
    role = create(:role, account: hotel.account)
    slugs.each { |slug| grant_permission(role, slug) }
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/reservation-board" do
    let!(:booking) { create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days) }

    before do
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    end

    it "responds successfully and includes the required modal structures" do
      sign_in_with_permissions("manage_bookings")

      get hotel_reservation_board_index_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("id=\"reservation-board-booking-sheet\"")
      expect(response.body).to include("id=\"reservation_board_booking_sheet_content\"")
    end

    it "displays rates in empty cells when a rate plan is present" do
      rate_plan = create(:rate_plan, room_type: room_type, name: "Standard Rate")
      create(:room_rate, rate_plan: rate_plan, room_type: room_type, date: Date.current + 3.days, price: 250, currency: "MYR")

      sign_in_with_permissions("manage_bookings")

      get hotel_reservation_board_index_path(hotel, filters: { rate_plan_name: "Standard Rate" })

      expect(response).to have_http_status(:success)
      expect(response.body).to include("250")
    end
  end
end
