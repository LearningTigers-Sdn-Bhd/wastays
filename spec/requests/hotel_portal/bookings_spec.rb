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

    it "renders hotel portal links with hotel slug in the path for superadmin" do
      superadmin = create(:user, :superadmin)
      sign_in_as(superadmin)

      get "/hotel/#{hotel.id}/bookings"

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(href="/hotel/#{hotel.slug}/arrivals"))
      expect(response.body).to include(%(href="/hotel/#{hotel.slug}/bookings"))
      expect(response.body).to include(%(href="/hotel/#{hotel.slug}/audit_logs"))
    end
  end

  describe "GET /show" do
    it "returns http success" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Room")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101", room_type_snapshot: { "name" => room_type.name }, quantity: 1, subtotal: booking.total_amount)
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")

      get "/hotel/#{hotel.id}/bookings/#{booking.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Open Room Readiness")
      expect(response.body).to include("Pending Cleaning")
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
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_in", params: { checked_in_at: Time.current.to_s }
      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.reload.checked_in_at).to be_present
    end
  end

  describe "POST /check_out" do
    it "updates the booking status and redirects within the hotel path" do
      booking.update!(status: 'checked_in')
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_out", params: { checked_out_at: Time.current.to_s }
      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(booking.reload.status).to eq("completed")
      expect(booking.reload.checked_out_at).to be_present
    end
  end

  describe "POST /cancel" do
    it "redirects within the hotel path" do
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/cancel"
      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    end
  end

  describe "GET /stay_price" do
    let(:room_type) { create(:room_type, hotel: hotel, base_price: 100) }

    it "returns the total amount for the stay" do
      get "/hotel/#{hotel.id}/bookings/stay_price", params: {
        room_type_id: room_type.id,
        check_in: Date.current.to_s,
        check_out: (Date.current + 2.days).to_s
      }

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to eq({ "total_amount" => "200.0" })
    end

    it "returns 0 if params are missing" do
      get "/hotel/#{hotel.id}/bookings/stay_price"

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)).to eq({ "total_amount" => 0 })
    end
  end

  describe "GET /availability" do
    let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101", "102" ]) }

    it "returns room options including disabled non-ready rooms" do
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")

      get "/hotel/#{hotel.id}/bookings/availability", params: {
        room_type_id: room_type.id,
        check_in: Date.current.to_s,
        check_out: (Date.current + 1.day).to_s
      }

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)

      expect(body["available_rooms"]).to include("102")
      expect(body["available_rooms"]).not_to include("101")
      option_101 = body["room_options"].find { |opt| opt["room_number"] == "101" }
      expect(option_101["selectable"]).to be(false)
      expect(option_101["label"]).to eq("101 (Pending Cleaning)")
    end
  end
end
