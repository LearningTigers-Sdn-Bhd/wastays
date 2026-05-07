# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomStatusBoard", type: :request do
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

  def sign_in_with_account_permission(*slugs)
    user = create(:user)
    hotel_role = create(:role, account: hotel.account)
    create(:user_hotel_access, user: user, hotel: hotel, role: hotel_role)

    account_role = create(:role, account: user.account)
    slugs.each { |slug| grant_permission(account_role, slug) }
    create(:user_role, user: user, role: account_role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/room-status" do
    it "responds successfully for users with view_room_readiness permission" do
      sign_in_with_permissions("view_room_readiness")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
    end

    it "allows account-level view_room_readiness permission alone" do
      sign_in_with_account_permission("view_room_readiness")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
    end

    it "responds successfully for users with manage_room_status permission" do
      sign_in_with_permissions("manage_room_status")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
    end

    it "redirects users without room status permissions" do
      user = create(:user)
      create(:user_hotel_access, user: user, hotel: hotel, role: create(:role, account: hotel.account))
      sign_in_as(user)

      get hotel_room_status_board_path(hotel)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("not authorized")
    end

    it "allows account-level room status permissions alone" do
      sign_in_with_account_permission("manage_room_status")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
    end

    it "renders occupancy block for bookings that start before the selected board window" do
      sign_in_with_permissions("view_room_readiness")
      start_date = Date.new(2026, 5, 7)
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
end
