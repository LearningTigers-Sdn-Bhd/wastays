require 'rails_helper'

RSpec.describe "HotelPortal::Bookings", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 3, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel, status: 'approved') }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role.permissions << (Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings'))
    role.permissions << (Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings'))
    role.permissions << (Permission.find_by(slug: 'post_folio_charges') || create(:permission, slug: 'post_folio_charges'))
    role.permissions << (Permission.find_by(slug: 'post_folio_payments') || create(:permission, slug: 'post_folio_payments'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def booking_details_path(booking, **params)
    hotel_booking_workspace_path(hotel, booking, { tab: "booking_details" }.merge(params))
  end

  def folio_operations_path(booking, folio_id: nil, **params)
    query = { tab: "folio_operations" }.merge(params)
    query[:folio_id] = folio_id if folio_id.present?
    hotel_booking_workspace_path(hotel, booking, query)
  end

  describe "GET /index" do
      before do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Room")
      BookingRoom.create!(booking: booking, room_type: room_type, room_type_snapshot: { "name" => room_type.name }, subtotal: booking.total_amount)
      create(:pre_checkin, booking: booking, status: "completed", document_status: "uploaded")
    end

    it "permanently redirects to Reservations" do
      get "/hotel/#{hotel.id}/bookings"
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(hotel_front_desk_path(hotel, tab: "bookings", view: "list"))
    end

    it "hides booking creation actions from read-only users" do
      role.permissions.delete(Permission.find_by!(slug: "manage_bookings"))

      get hotel_front_desk_path(hotel), params: { tab: "bookings", view: "list" }

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(hotel_booking_action_quick_booking_path(hotel))
      expect(response.body).not_to include(hotel_booking_action_walk_in_check_in_path(hotel))
      expect(response.body).not_to include(hotel_booking_action_backdated_check_in_path(hotel))
    end

    it "renders dashboard page without stale hotel booking path helpers" do
      get "/hotel/#{hotel.id}/dashboard"

      expect(response).to have_http_status(:success)
    end

    it "renders hotel portal links with hotel slug in the path for superadmin" do
      superadmin = create(:user, :superadmin)
      sign_in_as(superadmin)

      get hotel_front_desk_path(hotel), params: { tab: "bookings", view: "list" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(href="/hotel/#{hotel.slug}/front-desk"))
      expect(response.body).to include(%(href="/hotel/#{hotel.slug}/settings/general"))
    end
  end

  describe "GET /show" do
    it "renders a staff-friendly filtered booking history" do
      create(
        :booking_audit_log,
        hotel: hotel,
        auditable: booking,
        user: user,
        action_type: "cancel",
        category: "status",
        source: "staff",
        old_value: { "status" => "confirmed" },
        new_value: { "status" => "cancelled" },
        metadata: { "reason" => "Guest requested cancellation" }
      )

      get booking_details_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="booking-workspace"')
      expect(response.body).to include("Overview")
      expect(response.body).to include(booking.confirmation_token)
    end

    it "returns http success" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Room")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101", room_type_snapshot: { "name" => room_type.name }, subtotal: booking.total_amount)
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

      get booking_details_path(booking)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Stay")
      expect(response.body).to include("Room 101")
      expect(response.body).to include("Reservations")
      expect(Nokogiri::HTML(response.body).at_css("a[aria-label='Back to Reservations']")&.[]("href")).to eq(hotel_front_desk_path(hotel, tab: "bookings", view: "list"))
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include(%(href="#{folio_operations_path(booking)}"))
    end

    it "renders URL-addressable booking show tab panels" do
      get hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="booking-workspace"')
      expect(response.body).to include('data-testid="booking-workspace"')
    end

    it "renders reference IDs, booking source, and the refreshed guest records table" do
      booking.update!(
        adults: 3,
        children: 1,
        source: "booking_com",
        reservation_number: 12,
        guest_registration_number: 34,
        external_reference: "OTA-55",
        channel_manager_reference: "CM-66",
        guest_country: "Malaysia"
      )
      guest = create(:guest, name: "Additional Guest", country: "Singapore")
      create(:booking_guest, booking: booking, guest: guest, is_primary: false)

      get booking_details_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("References")
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include(booking.formatted_reservation_number)
      expect(response.body).to include(booking.formatted_guest_registration_number)
      expect(response.body).to include("OTA-55")
      expect(response.body).to include("CM-66")
      expect(response.body).to include('data-testid="booking-workspace"')
    end

    it "renders empty reference values and hides the guest-record warning when occupancy is fully registered" do
      booking.update!(adults: 2, children: 0, external_reference: nil, channel_manager_reference: nil)
      create(:booking_guest, booking: booking, is_primary: false)

      get booking_details_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("References")
      expect(response.body).to include("External")
      expect(response.body).to include("Channel Manager")
      expect(response.body).not_to include("have not been added to the guest records")
    end

    it "renders successfully when booking has complaint requests" do
      create(:complaint_request, booking: booking, status: "pending", complaint_details: "Broken AC")
      get booking_details_path(booking)
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="booking-workspace"')
      expect(response.body).to include("Overview")
    end

    it "renders folio actions for matching granular permissions" do
      grant_permission("post_folio_payments")
      grant_permission("post_folio_charges")
      create(:booking_folio, booking: booking, hotel: hotel, status: "open")

      get folio_operations_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Post Payment")
      expect(response.body).to include("Post Charge")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).not_to include("Post Adjustment")
    end

    it "filters folio adjustment categories by granular permission" do
      grant_permission("post_folio_write_offs")
      create(:booking_folio, booking: booking, hotel: hotel, status: "open")

      get folio_operations_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Post Adjustment")

      get new_hotel_folio_transaction_path(hotel, booking, transaction_type: "adjustment", active_folio_id: booking.booking_folio.id),
        headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('value="write_off"')
      expect(response.body).not_to include('value="correction"')
      expect(response.body).not_to include('value="discount"')
    end

    it "renders the compact folio summary and grouped ledger" do
      booking.update!(currency: "SGD", check_out: Date.current + 2.days)
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 125, description: "Room charge")
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 50, description: "Booking payment")
      create(:folio_forecasted_charge, booking_folio: folio, stay_date: Date.current + 1.day, amount: 75, description: "Future room charge")

      get folio_operations_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('id="folio-operations-heading"')
      expect(response.body).to include("Guest Folio")
      expect(response.body).to include('data-testid="booking-workspace"')
      expect(response.body).to include("SGD 150.00")
      expect(response.body).to include("Upcoming Charges")
      expect(response.body).to include("Room charge")
      expect(response.body).to include('data-section="posted"')
      expect(response.body).to include('aria-expanded="false"')
      expect(response.body).to include('data-section="forecasted"')
      expect(response.body).to include('data-folio-ledger-section-param="forecasted"')
      expect(response.body).to include("Future room charge")
      html = Nokogiri::HTML(response.body)
      expect(html.css("tr[data-section='posted']").all? { |row| !row["class"].to_s.split.include?("hidden") }).to be(true)
      expect(html.css("tr[data-section='forecasted']").all? { |row| row["class"].to_s.split.include?("hidden") }).to be(true)
    end
  end

  describe "PATCH /update" do
    it "redirects within the hotel path" do
      patch "/hotel/#{hotel.id}/bookings/#{booking.id}", params: { booking: { status: "confirmed" } }
      expect(response).to redirect_to(booking_details_path(booking))
    end

    it "does not change lifecycle status through booking params" do
      patch "/hotel/#{hotel.id}/bookings/#{booking.id}", params: { booking: { status: "checked_in", guest_name: "Updated Guest" } }

      expect(response).to redirect_to(booking_details_path(booking))
      expect(booking.reload.status).to eq("confirmed")
      expect(booking.guest_name).to eq("Updated Guest")
    end

    it "updates the booking source from the manual/OTA dropdown, even when channel-managed" do
      channel_managed_booking = create(:booking, hotel: hotel, source: "internal", channel_manager_reference: "channex-123")

      patch "/hotel/#{hotel.id}/bookings/#{channel_managed_booking.id}", params: { booking: { source: "booking_com" } }

      expect(response).to redirect_to(booking_details_path(channel_managed_booking))
      expect(channel_managed_booking.reload.source).to eq("booking_com")
    end
  end

  describe "POST /booking-actions/new-booking" do
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

    it "creates and redirects from the booking action sheet" do
      post hotel_booking_action_new_booking_path(hotel), params: { booking: booking_params }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, Booking.last))
    end

    it "renders validation errors inside the booking action sheet" do
      post hotel_booking_action_new_booking_path(hotel),
           params: { booking: booking_params.merge(guest_name: "") },
           headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('target="booking_action_sheet"')
      expect(response.body).to include("Guest name can&#39;t be blank")
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
      expect(JSON.parse(response.body)).to include(
        "total_amount" => "200.0",
        "room_total" => "200.0",
        "tax_total" => 0,
        "tax_lines" => []
      )
    end

    it "separates tourism tax from payable taxes for foreign guests" do
      hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      room_code.update!(is_taxable: true)
      room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
      room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")

      get "/hotel/#{hotel.id}/bookings/stay_price", params: {
        room_type_id: room_type.id,
        check_in: Date.current.to_s,
        check_out: (Date.current + 2.days).to_s,
        guest_country: "Singapore"
      }

      body = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(body["total_amount"].to_d).to eq(216.to_d)
      expect(body["room_total"].to_d).to eq(200.to_d)
      expect(body["tax_total"].to_d).to eq(16.to_d)
      expect(body["tourism_tax_total"].to_d).to eq(20.to_d)
      expect(body["tax_lines"].map { |line| line["type"] }).to include("sst", "tourism_tax")
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
      rate_plan = create(:rate_plan, room_type: room_type, name: "Premium Rate")
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
      room_type.rate_plans.destroy_all
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
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

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
      expect(option_101["label"]).to eq("101 (Dirty)")
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
