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

    it "hides booking creation actions from read-only users" do
      role.permissions.delete(Permission.find_by!(slug: "manage_bookings"))

      get hotel_bookings_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include(hotel_booking_transaction_new_booking_path(hotel))
      expect(response.body).not_to include(hotel_booking_transaction_walk_in_check_in_path(hotel))
      expect(response.body).not_to include(hotel_booking_transaction_backdated_check_in_path(hotel))
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

  describe "GET /booking-transactions/new-booking" do
    it "renders the offcanvas frame" do
      get hotel_booking_transaction_new_booking_path(hotel), headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
      expect(response.body).to include("New booking")
    end
  end

  describe "GET /show" do
    it "returns http success" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Room")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101", room_type_snapshot: { "name" => room_type.name }, quantity: 1, subtotal: booking.total_amount)
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

      get "/hotel/#{hotel.id}/bookings/#{booking.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Stay Details")
      expect(response.body).to include("Room 101")
      expect(response.body).to include("Operations")
      expect(response.body).to include(%(href="#{hotel_bookings_path(hotel)}">Bookings</a>))
      expect(response.body).to include(booking.confirmation_token)
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

      get hotel_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("References IDs")
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include(booking.formatted_reservation_number)
      expect(response.body).to include(booking.formatted_guest_registration_number)
      expect(response.body).to include("OTA-55")
      expect(response.body).to include("CM-66")
      expect(response.body).to include("Source: Booking Com")
      expect(response.body.scan("Source").size).to eq(1)
      expect(response.body).to include("2 registered guests")
      expect(response.body).to include("Add Additional Guest")
      expect(response.body).to include(hotel_booking_show_action_manage_guest_path(hotel, booking))
      expect(response.body).not_to include("edit-primary-guest-modal")
      expect(response.body).not_to include("add-additional-guest")
      expect(response.body).to include("Guest Type")
      expect(response.body).to include("Guest Reg No.")
      expect(response.body).to include("Country")
      expect(response.body.scan(">#{booking.formatted_guest_registration_number}<").size).to eq(3)
      expect(response.body).to include("Primary")
      expect(response.body).to include("Additional")
      expect(response.body).to include("w-full table-fixed")
      expect(response.body).not_to include("min-w-[1050px]")
      expect(response.body).to include("This booking has 2 guests that have not been added to the guest records.")
      expect(response.body).not_to include("No additional guests added.")
    end

    it "renders empty reference values and hides the guest-record warning when occupancy is fully registered" do
      booking.update!(adults: 2, children: 0, external_reference: nil, channel_manager_reference: nil)
      create(:booking_guest, booking: booking, is_primary: false)

      get hotel_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("References IDs")
      expect(response.body).to include("External")
      expect(response.body).to include("Channel Manager")
      expect(response.body).not_to include("have not been added to the guest records")
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

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Add Payment")
      expect(response.body).to include("Add Charge")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).not_to include("Add Adjustment")
    end

    it "filters folio adjustment categories by granular permission" do
      grant_permission("post_folio_write_offs")
      create(:booking_folio, booking: booking, hotel: hotel, status: "open")

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Add Adjustment")
      expect(response.body).to include('value="write_off"')
      expect(response.body).not_to include('value="correction"')
      expect(response.body).not_to include('value="discount"')
    end

    it "renders the compact folio summary and grouped ledger" do
      booking.update!(currency: "SGD", check_out: Date.current + 2.days)
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      charge = create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 125, description: "Room charge")
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 50, description: "Booking payment")
      create(:folio_forecasted_charge, booking_folio: folio, stay_date: Date.current + 1.day, amount: 75, description: "Future room charge")

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Folio #{booking.confirmation_token}")
      expect(response.body).to include("Guest")
      expect(response.body).to include("Stay")
      expect(response.body).to include("Back to Booking")
      expect(response.body).to include("Operations")
      expect(response.body).to include(%(href="#{hotel_bookings_path(hotel)}">Bookings</a>))
      expect(response.body).to include(%(href="#{hotel_booking_path(hotel, booking)}"))
      expect(response.body).to include("Folio Ledger")
      expect(response.body).to include("Outstanding")
      expect(response.body).to include("Posted Charges")
      expect(response.body).to include("Forecasted")
      expect(response.body).to include("Stay Total")
      expect(response.body).to include("SGD 150.00")
      expect(response.body).to include("SGD 200.00")
      expect(response.body).to include("Posted Transactions")
      expect(response.body).to include("Upcoming / Forecasted Charges")
      expect(response.body).to include("##{charge.id}")
      expect(response.body).to include('data-section="posted"')
      expect(response.body).to include('aria-expanded="true"')
      expect(response.body).to include('data-section="forecasted"')
      expect(response.body).to include('data-folio-ledger-section-param="forecasted"')
      expect(response.body).not_to include('aria-expanded="false"')
      expect(response.body).to include("Future room charge")
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

  describe "GET /checkout" do
    it "renders the checkout sheet in the offcanvas frame" do
      grant_permission("execute_folio_refunds")
      booking.update!(check_out: Date.current + 1.day)
      booking.transition_status_to!("checked_in", event: "check_in")
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      room_type = create(:room_type, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 100.0)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 140.0)

      get hotel_booking_transaction_check_out_path(hotel, booking), headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"')
      expect(response.body).to include("Step 1 of 2")
      expect(response.body).to include("Complete Checkout")
      expect(response.body).to include("Record Refund")
      expect(response.body).not_to include("Post Charges")
      expect(response.body).not_to include("Post Payment")
      expect(response.body).not_to include("Post Adjustment")
      expect(response.body).to include("Pending")
      expect(response.body).to include("Forecast charges to post")
      expect(response.body).to include("Existing transactions")
      expect(response.body).to include("Early checkout charge - Night 1")
      expect(response.body).to include("Outstanding balance")
      expect(response.body).to include('data-checkout-summary="true"')
      expect(response.body).to include('data-checkout-card="details"')
      expect(response.body).to include('data-checkout-card="early-departure"')
      expect(response.body).to include("border-t border-slate-200 bg-white")
      expect(response.body).not_to include("Checkout Time")
      expect(response.body).not_to include("Resolve Balance")
    end

    it "renders only the checkout details card for a scheduled checkout" do
      booking.update!(check_out: Date.current)
      booking.transition_status_to!("checked_in", event: "check_in")
      create(:booking_folio, booking: booking, hotel: hotel, status: "open")

      get hotel_booking_transaction_check_out_path(hotel, booking), headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-checkout-card="details"')
      expect(response.body).not_to include('data-checkout-card="early-departure"')
      expect(response.body.scan("Ready for checkout").size).to eq(1)
    end
  end

  describe "POST /booking-transactions/new-booking" do
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

    it "creates and redirects from the shared transaction sheet" do
      post hotel_booking_transaction_new_booking_path(hotel), params: { booking: booking_params }

      expect(response).to redirect_to(hotel_booking_path(hotel, Booking.last))
    end

    it "renders validation errors inside the offcanvas frame" do
      post hotel_booking_transaction_new_booking_path(hotel),
           params: { booking: booking_params.merge(guest_name: "") },
           headers: { "Turbo-Frame" => "offcanvas_drawer" }

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

    it "returns turbo stream completion to the reservation board" do
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_in",
           params: { checked_in_at: Time.current.to_s },
           headers: { "Accept" => "text/vnd.turbo-stream.html", "Referer" => board_hotel_bookings_url(hotel) }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_offcanvas"')
      expect(response.body).to include(%(url="#{board_hotel_bookings_path(hotel)}"))
    end

    it "renders the booking show page on turbo failures outside the reservation board" do
      booking = create(:booking, hotel: hotel, status: "pending")

      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_in",
           params: { checked_in_at: Time.current.to_s },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Cannot check in booking with status pending")
      expect(response.body).to include("Stay Details")
    end
  end

  describe "POST /check_out" do
    it "updates the booking status and redirects to the booking page with checkout_success" do
      booking.transition_status_to!("checked_in", event: "check_in")
      folio = create(:booking_folio, booking: booking, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100.0)

      post "/hotel/#{hotel.id}/bookings/#{booking.id}/check_out",
           params: { checked_out_at: Time.current.to_s },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_offcanvas"')
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_path(hotel, booking, checkout_success: true)))
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

    it "posts checkout settlement and redirects to the booking page with checkout_success" do
      grant_permission("post_folio_payments")
      booking.transition_status_to!("checked_in", event: "check_in")
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

      post check_out_hotel_booking_path(hotel, booking),
        params: {
          checkout_sheet: "1",
          checked_out_at: Time.current.to_s,
          checkout_payment_method: "cash",
          checkout_payment_amount: "100.00",
          checkout_payment_reference: "RCPT-1"
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_offcanvas"')
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_path(hotel, booking, checkout_success: true)))
      expect(booking.reload.status).to eq("completed")
      expect(folio.reload.status).to eq("closed")
      expect(folio.folio_transactions.payment.last.description).to include("RCPT-1")
    end

    it "returns timeline-board checkout-sheet submissions to the Booking Timeline Board" do
      booking.transition_status_to!("checked_in", event: "check_in")
      create(:booking_folio, booking: booking, hotel: hotel, status: "open")

      post check_out_hotel_booking_path(hotel, booking),
        params: {
          checkout_sheet: "1",
          source: "booking_timeline_board",
          checked_out_at: Time.current.to_s
        }

      expect(response).to redirect_to(board_hotel_bookings_path(hotel))
      expect(booking.reload.status).to eq("completed")
    end

    it "posts early departure charge before checkout-sheet settlement and redirects" do
      grant_permission("post_folio_payments")
      booking.update!(check_out: Date.current + 2.days)
      booking.transition_status_to!("checked_in", event: "check_in")
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

      post check_out_hotel_booking_path(hotel, booking),
        params: {
          checkout_sheet: "1",
          checked_out_at: Time.current.to_s,
          apply_charge: "1",
          charge_amount: "50.00",
          checkout_payment_method: "cash",
          checkout_payment_amount: "150.00",
          checkout_payment_reference: "RCPT-ED"
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_offcanvas"')
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_path(hotel, booking, checkout_success: true)))
      expect(booking.reload.status).to eq("completed")
      expect(booking.check_out.to_date).to eq(Date.current)
      expect(folio.reload.status).to eq("closed")
      expect(folio.folio_transactions.charge.find_by(category: "early_departure_charge").amount).to eq(50.0)
      expect(folio.folio_transactions.payment.last.description).to include("RCPT-ED")
    end

    it "truncates checkout-sheet early departure without requiring a charge and redirects" do
      grant_permission("post_folio_payments")
      booking.update!(check_out: Date.current + 2.days)
      booking.transition_status_to!("checked_in", event: "check_in")
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

      post check_out_hotel_booking_path(hotel, booking),
        params: {
          checkout_sheet: "1",
          checked_out_at: Time.current.to_s,
          checkout_payment_method: "cash",
          checkout_payment_amount: "100.00",
          checkout_payment_reference: "RCPT-NO-PENALTY"
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_offcanvas"')
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_path(hotel, booking, checkout_success: true)))
      expect(booking.reload.status).to eq("completed")
      expect(booking.check_out.to_date).to eq(Date.current)
      expect(folio.reload.status).to eq("closed")
      expect(folio.folio_transactions.charge.where(category: "early_departure_charge")).to be_empty
    end

    it "posts early checkout charges for prepaid unused nights, closes the folio and redirects" do
      booking.update!(check_in: Date.current, check_out: Date.current + 1.day, total_amount: 932.40)
      booking.transition_status_to!("checked_in", event: "check_in")
      room_type = create(:room_type, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, subtotal: 932.40)
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "booking_payment", amount: 932.40)

      post check_out_hotel_booking_path(hotel, booking),
        params: {
          checkout_sheet: "1",
          checked_out_at: Time.current.to_s
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_offcanvas"')
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_path(hotel, booking, checkout_success: true)))
      expect(booking.reload.status).to eq("completed")
      expect(booking.check_out.to_date).to eq(Date.current)
      expect(folio.reload.status).to eq("closed")
      expect(folio.folio_transactions.charge.find_by(description: "Early checkout charge - Night 1").amount).to eq(932.40)
      expect(folio.outstanding_balance).to eq(0)
    end

    it "rolls back early departure charge and truncation when checkout validation fails" do
      grant_permission("post_folio_payments")
      booking.update!(check_in: 1.day.ago.to_date, check_out: Date.current + 1.day)
      booking.transition_status_to!("checked_in", event: "check_in")
      create(:booking_room, booking: booking, subtotal: 200.0)
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      original_check_out = booking.check_out

      post check_out_hotel_booking_path(hotel, booking),
        params: {
          checkout_sheet: "1",
          checked_out_at: Time.current.to_s,
          apply_charge: "1",
          charge_amount: "50.00",
          checkout_payment_method: "cash",
          checkout_payment_amount: "50.00",
          checkout_payment_reference: "RCPT-ROLLBACK"
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Missing nightly charges for")
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.check_out).to eq(original_check_out)
      expect(folio.reload.status).to eq("open")
      expect(folio.folio_transactions).to be_empty
    end

    it "rolls back checkout settlement when checkout validation fails" do
      grant_permission("post_folio_payments")
      booking.update!(check_in: 1.day.ago.to_date, check_out: Date.current)
      booking.transition_status_to!("checked_in", event: "check_in")
      create(:booking_room, booking: booking, subtotal: 100.0)
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

      post check_out_hotel_booking_path(hotel, booking),
        params: {
          checkout_sheet: "1",
          checked_out_at: Time.current.to_s,
          checkout_payment_method: "cash",
          checkout_payment_amount: "100.00",
          checkout_payment_reference: "RCPT-FAIL"
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Missing nightly charges for")
      expect(booking.reload.status).to eq("checked_in")
      expect(folio.reload.status).to eq("open")
      expect(folio.folio_transactions.payment).to be_empty
    end

    it "rejects unsupported checkout payment methods" do
      grant_permission("post_folio_payments")
      booking.transition_status_to!("checked_in", event: "check_in")
      folio = create(:booking_folio, booking: booking, hotel: hotel, status: "open")
      create(:folio_transaction, booking_folio: folio, transaction_type: :charge, category: "accommodation", amount: 100.0)

      post check_out_hotel_booking_path(hotel, booking),
        params: {
          checkout_sheet: "1",
          checked_out_at: Time.current.to_s,
          checkout_payment_method: "credit_card",
          checkout_payment_amount: "100.00"
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Checkout payment method is not supported")
      expect(booking.reload.status).to eq("checked_in")
      expect(folio.folio_transactions.payment).to be_empty
    end
  end

  describe "POST /process_late_checkout" do
    let!(:folio) { create(:booking_folio, booking: booking, hotel: hotel, status: "open") }
    let(:room_type) { create(:room_type, hotel: hotel, quantity: 10) }
    let(:new_checkout_date) { (booking.check_out + 1.day) }
    let(:new_checkout_param) { new_checkout_date.strftime("%Y-%m-%dT14:00") }

    before do
      grant_permission("post_folio_charges")
      create(:booking_room, booking: booking, room_type: room_type, quantity: 1, room_number: "101")
    end

    it "updates the checkout period and applies the charge" do
      booking.transition_status_to!("checked_in", event: "check_in") unless booking.checked_in?
      booking.transition_status_to!("review_due_out", event: "detect_late_checkout")

      post "/hotel/#{hotel.id}/bookings/#{booking.id}/process_late_checkout", params: {
        charge_type: "charge",
        amount: "150.00",
        check_out: new_checkout_param
      }

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))

      booking.reload
      expect(booking.check_out.to_date).to eq(new_checkout_date.to_date)
      expect(booking.status).to eq("checked_in")
      expect(folio.folio_transactions.where(category: "late_checkout_charge").sum(:amount)).to eq(150.0)
    end

    it "resolves late checkout without charge" do
      booking.transition_status_to!("checked_in", event: "check_in")
      booking.transition_status_to!("review_due_out", event: "detect_late_checkout")

      post "/hotel/#{hotel.id}/bookings/#{booking.id}/process_late_checkout", params: {
        charge_type: "none",
        check_out: new_checkout_param
      }

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))

      booking.reload
      expect(booking.status).to eq("checked_in")
      expect(booking.check_out.to_date).to eq(new_checkout_date.to_date)
      expect(folio.folio_transactions.where(category: "late_checkout_charge").count).to eq(0)
    end

    it "does not process a booking outside late checkout review" do
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/process_late_checkout", params: {
        charge_type: "charge",
        amount: "150.00",
        check_out: new_checkout_param
      }

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Booking is not pending late checkout review.")
      expect(folio.folio_transactions.where(category: "late_checkout_charge")).to be_empty
    end

    it "does not post a charge without folio charge permission" do
      role.permissions.delete(Permission.find_by!(slug: "post_folio_charges"))
      booking.transition_status_to!("checked_in", event: "check_in") unless booking.checked_in?
      booking.transition_status_to!("review_due_out", event: "detect_late_checkout")

      post "/hotel/#{hotel.id}/bookings/#{booking.id}/process_late_checkout", params: {
        charge_type: "charge",
        amount: "150.00",
        check_out: new_checkout_param
      }

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to include("post_folio_charges")
      expect(booking.reload.status).to eq("review_due_out")
      expect(folio.folio_transactions.where(category: "late_checkout_charge")).to be_empty
    end
  end

  describe "POST /cancel" do
    it "redirects within the hotel path" do
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/cancel", params: { cancellation_reason: "Guest requested cancellation" }
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
      expect(JSON.parse(response.body)).to include(
        "total_amount" => "200.0",
        "room_total" => "200.0",
        "tax_total" => 0,
        "tax_lines" => []
      )
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
