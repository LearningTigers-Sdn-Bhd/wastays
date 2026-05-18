require 'rails_helper'

RSpec.describe "HotelPortal::Bookings", type: :request do
  let(:hotel) { create(:hotel, status: 'approved') }
  let(:user) { create(:user) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role = create(:role, account: hotel.account)
    role.permissions << (Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings'))
    role.permissions << (Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings'))
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
      expect(response.body).to include("Stay & Room Details")
      expect(response.body).to include("Room 101")
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

    it "checks in when the timestamp is submitted through booking params" do
      checked_in_at = "2026-05-18T13:08"
      expected_checked_in_at = Time.find_zone!(user.time_zone).parse(checked_in_at)

      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_in",
           params: { booking: { checked_in_at: checked_in_at } }

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.checked_in_at.to_i).to eq(expected_checked_in_at.to_i)
    end

    it "returns turbo stream reload when requested from reservation board" do
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_in",
           params: { checked_in_at: Time.current.to_s },
           headers: { "Accept" => "text/vnd.turbo-stream.html", "Referer" => hotel_reservation_board_index_url(hotel) }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="reload"')
    end

    it "renders the booking show page on turbo failures outside the reservation board" do
      booking.update!(status: "pending")

      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_in",
           params: { checked_in_at: Time.current.to_s },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Cannot check in booking with status pending")
      expect(response.body).to include("Stay & Room Details")
    end
  end

  describe "POST /check_out" do
    it "updates the booking status and redirects within the hotel path" do
      booking.update!(status: 'checked_in')
      folio = create(:booking_folio, booking: booking, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)

      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_out", params: { checked_out_at: Time.current.to_s }

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(booking.reload.status).to eq("completed")
      expect(booking.reload.checked_out_at).to be_present
      expect(folio.reload.status).to eq("closed")
    end

    it "does not check out when the folio is unsettled" do
      booking.update!(status: 'checked_in')
      folio = create(:booking_folio, booking: booking, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_out", params: { checked_out_at: Time.current.to_s }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Cannot check out with outstanding balance")
      expect(booking.reload.status).to eq("checked_in")
      expect(folio.reload.status).to eq("open")
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

    it "includes the current booking's assigned room when exclude_booking_id is provided" do
      booking.update!(check_in: Date.current, check_out: Date.current + 2.days, status: "confirmed")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

      other_booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 2.days, status: "confirmed")
      create(:booking_room, booking: other_booking, room_type: room_type, room_number: "102")

      get "/hotel/#{hotel.id}/bookings/availability", params: {
        room_type_id: room_type.id,
        check_in: Date.current.to_s,
        check_out: (Date.current + 2.days).to_s,
        exclude_booking_id: booking.id
      }

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)

      expect(body["available_rooms"]).to include("101")
      expect(body["available_rooms"]).not_to include("102")
    end
  end
end
