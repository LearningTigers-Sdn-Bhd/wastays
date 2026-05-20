require 'rails_helper'

RSpec.describe "HotelPortal::Bookings", type: :request do
  let(:hotel) { create(:hotel, status: 'approved') }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role.permissions << (Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings'))
    role.permissions << (Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
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

  describe "GET /new" do
    it "redirects direct page requests to the bookings index" do
      get "/hotel/#{hotel.id}/bookings/new"

      expect(response).to redirect_to(hotel_bookings_path(hotel))
    end

    it "renders the offcanvas frame for turbo frame requests" do
      get "/hotel/#{hotel.id}/bookings/new", headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
      expect(response.body).to include("Add New Booking")
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

    it "renders folio actions for matching granular permissions" do
      grant_permission("post_folio_payments")
      grant_permission("post_folio_charges")
      create(:booking_folio, booking: booking, hotel: hotel, status: "open")

      get folio_hotel_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Post Payment")
      expect(response.body).to include("Post Charge")
      expect(response.body).not_to include("Record Refund")
      expect(response.body).not_to include("Post Adjustment")
    end

    it "filters folio adjustment categories by granular permission" do
      grant_permission("post_folio_write_offs")
      create(:booking_folio, booking: booking, hotel: hotel, status: "open")

      get folio_hotel_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Post Adjustment")
      expect(response.body).to include('value="write_off"')
      expect(response.body).not_to include('value="correction"')
      expect(response.body).not_to include('value="discount"')
    end
  end

  describe "PATCH /update" do
    it "redirects within the hotel path" do
      patch "/hotel/#{hotel.id}/bookings/#{booking.id}", params: { booking: { status: "confirmed" } }
      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
    end

    it "does not change lifecycle status through booking params" do
      patch "/hotel/#{hotel.id}/bookings/#{booking.id}", params: { booking: { status: "checked_in", guest_name: "Updated Guest" } }

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(booking.reload.status).to eq("confirmed")
      expect(booking.guest_name).to eq("Updated Guest")
    end
  end

  describe "POST /create" do
    let(:room_type) { create(:room_type, hotel: hotel, quantity: 2, room_numbers: [ "101", "102" ], base_price: 100) }
    let(:booking_params) do
      {
        guest_name: "Manual Guest",
        guest_email: "manual@example.com",
        guest_phone: "+60123456789",
        check_in: Date.current.to_s,
        check_out: (Date.current + 1.day).to_s,
        room_type_id: room_type.id,
        room_number: "101",
        adults: 2,
        children: 0
      }
    end

    before do
      dispatcher = instance_double(Notifications::Dispatcher, call: [])
      allow(Notifications::Dispatcher).to receive(:new).and_return(dispatcher)
      create(:room_rate, room_type: room_type, date: Date.current, price: 100, currency: hotel.default_currency.presence || "MYR")
    end

    it "returns a turbo redirect action for offcanvas submits" do
      post "/hotel/#{hotel.id}/bookings",
           params: { booking: booking_params },
           headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="redirect"')
      expect(response.body).to include(hotel_booking_path(hotel, Booking.last))
    end

    it "renders validation errors inside the offcanvas frame" do
      post "/hotel/#{hotel.id}/bookings",
           params: { booking: booking_params.merge(guest_name: "") },
           headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
      expect(response.body).to include("Guest name can&#39;t be blank")
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
      booking = create(:booking, hotel: hotel, status: "pending")

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
      booking.transition_status_to!("checked_in", event: "check_in")
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
      booking.transition_status_to!("checked_in", event: "check_in")
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

    it "uses the selected rate plan and falls back to base price for missing nightly rates" do
      rate_plan = create(:rate_plan, room_type: room_type)
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 150)

      get "/hotel/#{hotel.id}/bookings/stay_price", params: {
        room_type_id: room_type.id,
        rate_plan_id: rate_plan.id,
        check_in: Date.current.to_s,
        check_out: (Date.current + 2.days).to_s
      }

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)["total_amount"].to_d).to eq(250.to_d)
    end

    it "falls back to base pricing when the selected rate plan is stale" do
      get "/hotel/#{hotel.id}/bookings/stay_price", params: {
        room_type_id: room_type.id,
        rate_plan_id: 999_999,
        check_in: Date.current.to_s,
        check_out: (Date.current + 2.days).to_s
      }

      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)["total_amount"].to_d).to eq(200.to_d)
    end
  end

  describe "GET /rate_options" do
    let(:room_type) { create(:room_type, hotel: hotel, base_price: 100) }

    it "returns rate plans for the selected room type" do
      rate_plan = create(:rate_plan, room_type: room_type, name: "Flexible Rate")
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 125)

      get "/hotel/#{hotel.id}/bookings/rate_options", params: {
        room_type_id: room_type.id,
        check_in: Date.current.to_s,
        check_out: (Date.current + 1.day).to_s
      }

      expect(response).to have_http_status(:success)
      option = JSON.parse(response.body)["rate_options"].first
      expect(option).to include("id" => rate_plan.id, "name" => "Flexible Rate", "currency" => "MYR")
      expect(option["total_amount"].to_d).to eq(125.to_d)
    end

    it "ignores stop-sell restrictions unless staff chooses to respect them" do
      rate_plan = create(:rate_plan, room_type: room_type, name: "OTA Rate")
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 125, stop_sell: true)

      get "/hotel/#{hotel.id}/bookings/rate_options", params: {
        room_type_id: room_type.id,
        check_in: Date.current.to_s,
        check_out: (Date.current + 1.day).to_s
      }

      expect(JSON.parse(response.body)["rate_options"].map { |option| option["id"] }).to include(rate_plan.id)

      get "/hotel/#{hotel.id}/bookings/rate_options", params: {
        room_type_id: room_type.id,
        check_in: Date.current.to_s,
        check_out: (Date.current + 1.day).to_s,
        apply_stop_sell_restriction: "1"
      }

      expect(JSON.parse(response.body)["rate_options"].map { |option| option["id"] }).not_to include(rate_plan.id)
    end

    it "returns a base rate option when no rate plans exist" do
      get "/hotel/#{hotel.id}/bookings/rate_options", params: {
        room_type_id: room_type.id,
        check_in: Date.current.to_s,
        check_out: (Date.current + 2.days).to_s
      }

      option = JSON.parse(response.body)["rate_options"].first
      expect(option).to include("id" => nil, "name" => "Base Rate", "currency" => "MYR")
      expect(option["total_amount"].to_d).to eq(200.to_d)
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
