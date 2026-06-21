require "rails_helper"

RSpec.describe "HotelPortal::Folios", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 6, 18, 10, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_bookings) { Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View Bookings" } }

  before do
    role.permissions << view_bookings
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/folios" do
    it "renders the folio control page with sticky action columns and no posting actions" do
      booking = create_booking_with_folio(
        guest_name: "Amir Hakim",
        confirmation_token: "BK-8891",
        room_number: "204",
        folio_number: 232,
        charges: 200,
        payments: 80
      )

      get hotel_folios_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Folios")
      expect(response.body).to include("Review open balances, refund due folios, checkout readiness, and guest folio activity.")
      expect(response.body).to include("Guest / Booking")
      expect(response.body).to include("Folio Reference")
      expect(response.body).to include("Stay / Room")
      expect(response.body).to include("Financials")
      expect(response.body).to include("Status")
      expect(response.body).to include("Action")
      expect(response.body).to include("sticky right-0")
      expect(response.body).to include("View Folio")
      expect(response.body).to include("View Booking")
      expect(response.body).to include("#{hotel_folio_path(hotel, booking)}?origin=folios")
      expect(response.body).to include(hotel_booking_path(hotel, booking))
      expect(response.body).to include("MYR 120.00")
      expect(response.body).to include("Balance Due")
      expect(response.body).to include("rounded-lg bg-slate-900 px-3 py-1.5 text-xs font-black text-white")
      expect(response.body).to include("rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-black text-slate-700")
      expect(response.body).to include("border-emerald-200 bg-emerald-50 text-emerald-700")
      expect(response.body).to include("text-red-700")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).not_to include("Post Payment")
      expect(response.body).not_to include("Post Charge")
      expect(response.body).not_to include("Adjustment")
      expect(response.body).not_to include("Booking &rsaquo;")
      expect(response.body).not_to include("type=\"submit\" class=\"inline-flex items-center justify-center rounded-lg bg-slate-900")
    end

    it "links View Folio to the folios-origin show context" do
      booking = create_booking_with_folio(guest_name: "Amir Hakim", confirmation_token: "BK-8891", folio_number: 232, charges: 120)

      get hotel_folios_path(hotel)

      expect(response.body).to include(%(href="#{hotel_folio_path(hotel, booking)}?origin=folios"))
    end

    it "renders Needs Attention above the search toolbar" do
      create_booking_with_folio(guest_name: "Amir Hakim", confirmation_token: "BK-8891", folio_number: 232, charges: 120)

      get hotel_folios_path(hotel)

      expect(response.body.index("Needs Attention")).to be < response.body.index("Search guest, booking ref, folio ref, room...")
    end

    it "searches by guest, booking reference, folio number, and room" do
      create_booking_with_folio(guest_name: "Nur Aina", confirmation_token: "BK-8893", room_number: "110", folio_number: 234, payments: 80)
      create_booking_with_folio(guest_name: "Hanami Saki", confirmation_token: "BK-CUXKRP", room_number: "302", folio_number: 231, charges: 100, payments: 100)

      get hotel_folios_path(hotel), params: { query: "110" }

      expect(response).to have_http_status(:success)
      expect(results_text).to include("Nur Aina")
      expect(results_text).not_to include("Hanami Saki")

      get hotel_folios_path(hotel), params: { query: "234" }

      expect(results_text).to include("Nur Aina")
      expect(results_text).not_to include("Hanami Saki")
    end

    it "filters by balance due, refund due, due out, closed, and adjusted" do
      balance_due = create_booking_with_folio(guest_name: "Balance Guest", confirmation_token: "BK-BAL", folio_number: 301, charges: 150)
      refund_due = create_booking_with_folio(guest_name: "Credit Guest", confirmation_token: "BK-CRE", folio_number: 302, payments: 80)
      closed = create_booking_with_folio(guest_name: "Closed Guest", confirmation_token: "BK-CLO", folio_number: 303, charges: 90, payments: 90, status: "closed")
      adjusted = create_booking_with_folio(guest_name: "Adjusted Guest", confirmation_token: "BK-ADJ", folio_number: 304, adjustments: 20)

      get hotel_folios_path(hotel), params: { filter: "balance_due" }
      expect(results_text).to include(balance_due.guest_name)
      expect(results_text).not_to include(refund_due.guest_name)

      get hotel_folios_path(hotel), params: { filter: "refund_due" }
      expect(results_text).to include(refund_due.guest_name)
      expect(results_text).to include("MYR 80.00 credit")
      expect(results_text).not_to include(balance_due.guest_name)

      get hotel_folios_path(hotel), params: { filter: "due_out" }
      expect(results_text).to include(balance_due.guest_name)
      expect(results_text).not_to include(closed.guest_name)

      get hotel_folios_path(hotel), params: { filter: "closed" }
      expect(results_text).to include(closed.guest_name)
      expect(results_text).not_to include(balance_due.guest_name)

      get hotel_folios_path(hotel), params: { filter: "adjusted" }
      expect(results_text).to include(adjusted.guest_name)
      expect(results_text).not_to include(balance_due.guest_name)
    end

    it "does not sync Needs Attention with table search or filters" do
      create_booking_with_folio(guest_name: "Attention Guest", confirmation_token: "BK-ATT", folio_number: 351, charges: 200)
      create_booking_with_folio(guest_name: "Settled Guest", confirmation_token: "BK-SET", folio_number: 352, charges: 100, payments: 100)

      get hotel_folios_path(hotel), params: { query: "Settled" }

      expect(response.body).to include("Attention Guest")
      expect(results_text).to include("Settled Guest")
      expect(results_text).not_to include("Attention Guest")
    end

    it "shows operational blockers in Needs Attention, including unsynced completed refunds" do
      balance_due = create_booking_with_folio(guest_name: "Amir Hakim", confirmation_token: "BK-8891", folio_number: 401, charges: 120)
      refund_due = create_booking_with_folio(guest_name: "Nur Aina", confirmation_token: "BK-8893", folio_number: 402, payments: 80)
      unsynced = create_booking_with_folio(guest_name: "Daniel Lim", confirmation_token: "BK-8898", folio_number: 403, charges: 100, payments: 100)
      create(:refund_request, booking: unsynced, status: "completed", refund_amount: 45)

      get hotel_folios_path(hotel)

      expect(response.body).to include("Needs Attention")
      expect(response.body).to include(balance_due.guest_name)
      expect(response.body).to include("Guest owes hotel")
      expect(response.body).to include(refund_due.guest_name)
      expect(response.body).to include("Hotel owes guest")
      expect(response.body).to include(unsynced.guest_name)
      expect(response.body).to include("Completed refund is not synced to the folio")
    end

    it "scopes folios to the current hotel" do
      create_booking_with_folio(guest_name: "Visible Guest", confirmation_token: "BK-VIS", folio_number: 501, charges: 100)
      other_booking = create(:booking, hotel: other_hotel, guest_name: "Hidden Guest", confirmation_token: "BK-HID")
      create(:booking_folio, booking: other_booking, hotel: other_hotel, folio_number: 999)

      get hotel_folios_path(hotel)

      expect(response.body).to include("Visible Guest")
      expect(response.body).not_to include("Hidden Guest")
    end

    it "requires view booking permission" do
      role.permissions.delete(view_bookings)

      get hotel_folios_path(hotel)

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
    end
  end

  describe "GET /hotel/:hotel_id/folios/:booking_id" do
    it "uses booking navigation by default" do
      booking = create_booking_with_folio(guest_name: "Booking Origin", confirmation_token: "BK-BOOK", folio_number: 601, charges: 100)

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Back to Booking")
      expect(response.body).to include("Operations")
      expect(response.body).to include(%(href="#{hotel_bookings_path(hotel)}">Bookings</a>))
      expect(response.body).to include(%(href="#{hotel_booking_path(hotel, booking)}"))
      expect(response.body).not_to include("Back to All Folios")
    end

    it "uses folios navigation when opened from the folios index" do
      booking = create_booking_with_folio(guest_name: "Folio Origin", confirmation_token: "BK-FOLIO", folio_number: 602, charges: 100)

      get hotel_folio_path(hotel, booking, origin: "folios")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Back to All Folios")
      expect(response.body).to include("Finance")
      expect(response.body).to include(%(href="#{hotel_folios_path(hotel)}">Folios</a>))
      expect(response.body).to include(%(href="#{hotel_folio_path(hotel, booking)}?origin=folios"))
      expect(response.body).not_to include("Back to Booking")
    end

    it "renders combined folio details, checkout readiness metrics, and ready checkout status" do
      booking = create_booking_with_folio(
        guest_name: "Ready Guest",
        confirmation_token: "BK-READY",
        folio_number: 604,
        charges: 100,
        payments: 100,
        check_in: Date.new(2026, 6, 11),
        check_out: Date.new(2026, 6, 13)
      )

      get hotel_folio_path(hotel, booking)

      body = response.body

      expect(response).to have_http_status(:success)
      expect(body).to include("Stay / Nights")
      expect(body).to include("11 Jun 2026 - 13 Jun 2026 / 2 Nights")
      expect(body).to include("Folio Type")
      expect(body).to include("Payments / Refunds")
      expect(body).to include("Checkout Readiness")
      expect(body).not_to include("Upcoming Lines")
      expect(body).not_to include("Close Readiness")
      expect(body).to include("Checkout Status")
      expect(body).to include("Ready for checkout")
      expect(body).to include("Balance settled · No upcoming charges · Payments/refunds synced")
      expect(body).to include(%(href="#{hotel_booking_path(hotel, booking)}"))
      expect(body).to include("Go to Booking")
      expect(body).not_to include("Close Folio")
    end

    it "renders blocked checkout status with blocker summary" do
      booking = create_booking_with_folio(guest_name: "Blocked Guest", confirmation_token: "BK-BLOCK", folio_number: 605, charges: 100, check_out: Date.current + 1.day)
      create(:folio_forecasted_charge, booking_folio: booking.booking_folio, amount: 30, stay_date: Date.current, charge_kind: "accommodation")

      get hotel_folio_path(hotel, booking)

      body = response.body

      expect(response).to have_http_status(:success)
      expect(body).to include("Not ready for checkout")
      expect(body).to include("Guest owes MYR 130.00 · 1 upcoming charge pending")
      expect(body).to include(%(href="#{hotel_booking_path(hotel, booking)}"))
      expect(body).not_to include("Close Folio: Not ready")
    end

    it "shows normal actions on an open business date when the user has permission" do
      %w[
        post_folio_charges
        post_folio_payments
        execute_folio_refunds
        post_folio_adjustments
      ].each { |slug| grant_permission(slug) }
      booking = create_booking_with_folio(guest_name: "Action Guest", confirmation_token: "BK-ACT", folio_number: 606, charges: 100)

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Post Payment")
      expect(response.body).to include("Post Charge")
      expect(response.body).to include("Post Adjustment")
      expect(response.body).to include("More Actions")
      expect(response.body).to include("Issue Refund")

      refund_form = Nokogiri::HTML(response.body).at_css("#folio-refund-modal-#{booking.id} form")
      expect(refund_form).to be_present
      expect(refund_form.text).to include("Refund Source")
      expect(refund_form.at_css(%(select[name="folio_transaction[refund_source]"][required]))).to be_present
      expect(refund_form.at_css(%(input[name="folio_transaction[category]"][value="refund"]))).to be_present
    end

    it "does not show normal actions on an open business date when the user lacks permission" do
      booking = create_booking_with_folio(guest_name: "No Permission Guest", confirmation_token: "BK-NOPERM", folio_number: 607, charges: 100)

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No posting actions available")
      expect(response.body).not_to include("Post Payment")
      expect(response.body).not_to include("Post Charge")
      expect(response.body).not_to include("Post Adjustment")
      expect(response.body).not_to include("More Actions")
      expect(response.body).not_to include("Issue Refund")
    end

    it "replaces normal actions with a night-audit-running message" do
      %w[
        manage_night_audit
        post_folio_charges
        post_folio_payments
        execute_folio_refunds
        post_folio_adjustments
        post_folio_corrections
      ].each { |slug| grant_permission(slug) }
      hotel.current_business_date_record.update!(status: "audit_running")
      night_audit = create(:night_audit, hotel: hotel, business_date: hotel.current_business_date, status: "running")
      booking = create_booking_with_folio(guest_name: "Audit Running Guest", confirmation_token: "BK-RUN", folio_number: 608, charges: 100)
      transaction = booking.booking_folio.folio_transactions.first

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Financial posting is temporarily unavailable.")
      expect(response.body).to include("Night audit is currently running for this business date.")
      expect(response.body).to include("View Night Audit")
      expect(response.body).to include(hotel_night_audit_path(hotel, night_audit))
      expect(response.body).not_to include("Post Payment")
      expect(response.body).not_to include("Post Charge")
      expect(response.body).not_to include("Post Adjustment")
      expect(response.body).not_to include("More Actions")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).not_to include(reverse_hotel_folio_transaction_path(hotel, booking, transaction))
    end

    it "replaces normal actions with a night-audit-blocked message" do
      %w[
        manage_night_audit
        post_folio_charges
        post_folio_payments
        execute_folio_refunds
        post_folio_adjustments
        post_folio_corrections
      ].each { |slug| grant_permission(slug) }
      hotel.current_business_date_record.update!(status: "audit_blocked")
      night_audit = create(:night_audit, hotel: hotel, business_date: hotel.current_business_date, status: "blocked")
      booking = create_booking_with_folio(guest_name: "Audit Blocked Guest", confirmation_token: "BK-BLOCKED", folio_number: 609, charges: 100)
      transaction = booking.booking_folio.folio_transactions.first

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Normal folio posting is blocked.")
      expect(response.body).to include("Night audit is blocked. Resolve blockers from the Night Audit page, then retry audit.")
      expect(response.body).to include("View Night Audit Blockers")
      expect(response.body).to include(resolve_hotel_night_audit_path(hotel, night_audit))
      expect(response.body).not_to include("Post Payment")
      expect(response.body).not_to include("Post Charge")
      expect(response.body).not_to include("Post Adjustment")
      expect(response.body).not_to include("More Actions")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).not_to include(reverse_hotel_folio_transaction_path(hotel, booking, transaction))
    end

    it "shows closed-folio actions state while preserving allowed ledger corrections" do
      %w[
        post_folio_charges
        post_folio_payments
        execute_folio_refunds
        post_folio_adjustments
        post_folio_corrections
        override_financial_date_lock
      ].each { |slug| grant_permission(slug) }
      booking = create_booking_with_folio(guest_name: "Closed Guest", confirmation_token: "BK-CLOSED", folio_number: 610, charges: 100, status: "closed")
      transaction = booking.booking_folio.folio_transactions.first

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Normal posting actions are unavailable for a closed folio.")
      expect(response.body).not_to include("Post Payment")
      expect(response.body).not_to include("Post Charge")
      expect(response.body).not_to include("Post Adjustment")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).to include(reverse_hotel_folio_transaction_path(hotel, booking, transaction))
    end

    it "renders one horizontal ledger table with posted balance as a section summary only" do
      booking = create_booking_with_folio(guest_name: "Ledger Guest", confirmation_token: "BK-LEDGER", folio_number: 603, charges: 100, payments: 40)
      create(:folio_forecasted_charge, booking_folio: booking.booking_folio, amount: 30, stay_date: Date.current, charge_kind: "accommodation")

      get hotel_folio_path(hotel, booking)

      html = Nokogiri::HTML(response.body)
      ledger = html.at_css("section[data-controller='folio-ledger']")
      headers = ledger.css("thead th").map { |header| header.text.squish }

      expect(response).to have_http_status(:success)
      expect(ledger.at_css(".overflow-x-auto")).to be_present
      expect(headers).to eq([ "Date", "Code", "Description / Reference", "Debit", "Credit", "Action" ])
      expect(ledger.text.squish).to include("Posted balance MYR 60.00")
      expect(ledger.text.squish).not_to include("Projected balance")
      expect(response.body).not_to include("posted-mobile")
      expect(response.body).not_to include("forecasted-mobile")
    end
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def create_booking_with_folio(guest_name:, confirmation_token:, folio_number:, room_number: nil, charges: 0, payments: 0, adjustments: 0, status: "open", check_in: Date.current, check_out: Date.current)
    room_type = create(:room_type, hotel: hotel)
    booking = create(
      :booking,
      hotel: hotel,
      guest_name: guest_name,
      confirmation_token: confirmation_token,
      check_in: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: check_in, kind: :check_in),
      check_out: Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: check_out, kind: :check_out)
    )
    create(:booking_room, booking: booking, room_type: room_type, room_number: room_number) if room_number.present?
    folio = create(:booking_folio, booking: booking, hotel: hotel, folio_number: folio_number, status: status)
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: charges) if charges.positive?
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: payments) if payments.positive?
    create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment", category: "adjustment", amount: adjustments) if adjustments.positive?
    folio.update!(updated_at: Time.current) if status == "closed"
    booking
  end

  def results_text
    Nokogiri::HTML(response.body).at_css("turbo-frame#folios_results").text
  end
end
