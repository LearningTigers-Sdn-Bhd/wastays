# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::ReservationVouchers", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_bookings") { |entry| entry.name = "Manage Bookings" }
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/bookings/:booking_id/reservation_voucher" do
    it "returns the booking voucher as an inline PDF" do
      get hotel_booking_reservation_voucher_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.content_type).to start_with("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(
        "inline",
        "wastays-reservation-voucher-#{booking.confirmation_token}.pdf"
      )
      expect(response.body).to start_with("%PDF")
    end

    it "denies staff without manage_bookings permission" do
      staff = create(:user)
      other_role = create(:role, account: hotel.account)
      create(:user_hotel_access, user: staff, hotel: hotel, role: other_role)
      sign_in_as(staff)

      get hotel_booking_reservation_voucher_path(hotel, booking)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end

    it "does not expose another hotel's booking" do
      other_booking = create(:booking)

      get hotel_booking_reservation_voucher_path(hotel, other_booking)

      expect(response).to have_http_status(:not_found)
    end
  end
end
