# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::BookingSummaries", type: :request do
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

  describe "GET /hotel/:hotel_id/bookings/:booking_id/booking_summary" do
    it "returns the booking summary as an inline PDF" do
      get hotel_booking_booking_summary_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.content_type).to start_with("application/pdf")
      expect(response.headers["Content-Disposition"]).to include(
        "inline",
        "wastays-booking-summary-#{booking.confirmation_token}.pdf"
      )
      expect(response.body).to start_with("%PDF")
    end

    # Staff land on a room far more often than on the group, so resolving upward is the
    # ordinary path rather than an edge case.
    it "reports the group's position when the booking belongs to a group" do
      group_booking = create(:group_booking, hotel: hotel)
      room = create(:booking, hotel: hotel, group_booking: group_booking, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group_booking, group_position: 2)

      get hotel_booking_booking_summary_path(hotel, room)

      expect(response).to have_http_status(:success)
      expect(response.headers["Content-Disposition"]).to include(
        "wastays-booking-summary-#{group_booking.confirmation_token}.pdf"
      )
      expect(PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join)
        .to include("GROUP BOOKING SUMMARY", group_booking.name)
    end

    it "denies staff without manage_bookings permission" do
      staff = create(:user)
      other_role = create(:role, account: hotel.account)
      create(:user_hotel_access, user: staff, hotel: hotel, role: other_role)
      sign_in_as(staff)

      get hotel_booking_booking_summary_path(hotel, booking)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end

    it "does not expose another hotel's booking" do
      get hotel_booking_booking_summary_path(hotel, create(:booking))

      expect(response).to have_http_status(:not_found)
    end
  end
end
