require 'rails_helper'

RSpec.describe "HotelPortal::Bookings", type: :request do
  let(:hotel) { create(:hotel, status: 'approved') }
  let(:user) { create(:user) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
      before do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Room")
      BookingRoom.create!(booking: booking, room_type: room_type, room_type_snapshot: { "name" => room_type.name }, quantity: 1, subtotal: booking.total_amount)
      create(:pre_checkin, booking: booking, status: "completed", document_status: "uploaded")
    end

    it "returns http success" do
      get "/hotel/#{hotel.id}/bookings"
      expect(response).to have_http_status(:success)
    end

    it "renders dashboard page without stale hotel booking path helpers" do
      get "/hotel/#{hotel.id}/dashboard"

      expect(response).to have_http_status(:success)
    end

    it "renders hotel portal links with hotel id in the path for superadmin" do
      superadmin = create(:user, :superadmin)
      sign_in_as(superadmin)

      get "/hotel/#{hotel.id}/bookings"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(href="/hotel/#{hotel.id}/arrivals"))
      expect(response.body).to include(%(href="/hotel/#{hotel.id}/bookings"))
      expect(response.body).to include(%(href="/hotel/#{hotel.id}/audit_logs"))
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/hotel/#{hotel.id}/bookings/#{booking.id}"
      expect(response).to have_http_status(:success)
    end

    it "renders successfully when booking has complaint requests" do
      create(:complaint_request, booking: booking, status: "pending", complaint_details: "Broken AC")
      get "/hotel/#{hotel.id}/bookings/#{booking.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Broken AC")
      expect(response.body).to include("pending")
    end
  end

  describe "PATCH /update" do
    it "redirects within the hotel path" do
      patch "/hotel/#{hotel.id}/bookings/#{booking.id}", params: { booking: { status: "confirmed" } }
      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    end
  end

  describe "POST /check_in" do
    it "updates the booking status and redirects within the hotel path" do
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_in"
      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.checked_in_at).to be_present
    end
  end

  describe "POST /check_out" do
    it "updates the booking status and redirects within the hotel path" do
      booking.update!(status: 'checked_in')
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_out"
      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(booking.reload.status).to eq("completed")
      expect(booking.checked_out_at).to be_present
    end
  end

  describe "POST /cancel" do
    it "redirects within the hotel path" do
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/cancel"
      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    end
  end
end
