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

  describe "GET .../reservation_voucher/pack" do
    let(:group_booking) { create(:group_booking, hotel: hotel) }
    let!(:first_room) { create(:booking, hotel: hotel, group_booking: group_booking, group_position: 1) }
    let!(:second_room) { create(:booking, hotel: hotel, group_booking: group_booking, group_position: 2) }

    it "returns every room in the group as one PDF" do
      get pack_hotel_booking_reservation_voucher_path(hotel, first_room)

      expect(response).to have_http_status(:success)
      expect(response.content_type).to start_with("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(
        "wastays-reservation-vouchers-#{group_booking.formatted_reservation_number}.pdf"
      )
      expect(PDF::Reader.new(StringIO.new(response.body)).pages.size).to eq(2)
    end

    # A booking that belongs to no group has nothing to pack.
    it "falls back to the single voucher for a booking outside a group" do
      get pack_hotel_booking_reservation_voucher_path(hotel, booking)

      expect(response).to redirect_to(hotel_booking_reservation_voucher_path(hotel, booking))
    end
  end
end
