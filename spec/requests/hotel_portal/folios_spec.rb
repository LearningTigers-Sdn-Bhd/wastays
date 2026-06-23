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
      expect(response.body).to include("Operations")
      expect(response.body).to include(%(href="#{hotel_bookings_path(hotel)}">Bookings</a>))
      expect(response.body).to include(%(href="#{hotel_booking_path(hotel, booking)}"))
      expect(response.body).to include("Generate Report")
      expect(response.body).not_to include("Back to Booking")
      expect(response.body).not_to include("Back to All Folios")
    end

    it "uses folios navigation when opened from the folios index" do
      booking = create_booking_with_folio(guest_name: "Folio Origin", confirmation_token: "BK-FOLIO", folio_number: 602, charges: 100)

      get hotel_folio_path(hotel, booking, origin: "folios")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Finance")
      expect(response.body).to include(%(href="#{hotel_folios_path(hotel)}">Folios</a>))
      expect(response.body).to include(%(href="#{hotel_folio_path(hotel, booking)}?origin=folios"))
      expect(response.body).to include("Generate Report")
      expect(response.body).not_to include("Back to All Folios")
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
      expect(body).to include("Booking Info")
      expect(body).to include("Stay / Nights")
      expect(body).to include("11 Jun 2026 - 13 Jun 2026 / 2 Nights")
      expect(body).to include("Currency")
      expect(body).not_to include("Folio Type")
      expect(body).to include("Payments / Refunds")
      expect(body).to include("Checkout Readiness")
      expect(body).not_to include("Upcoming Lines")
      expect(body).not_to include("Close Readiness")
      expect(body).not_to include("Checkout Status</h2>")
      expect(body).to include("Ready for checkout")
      expect(body).to include("Balance settled · No upcoming charges · Payments/refunds synced")
      expect(body).to include(%(href="#{hotel_booking_path(hotel, booking)}"))
      expect(body).not_to include("Go to Booking")
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
      expect(response.body).to include("Ledger Actions")
      expect(response.body).to include("Generate Report")
      expect(response.body).to include("Folio Ledger")
      expect(response.body).to include("Download PDF")
      expect(response.body).to include("Download CSV")
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :pdf))
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :csv))
      expect(response.body).to include("Booking Invoices")
      expect(response.body).to include("Available after checkout.")
      expect(response.body).to include("More Actions")
      expect(response.body).to include("Issue Refund")

      html = Nokogiri::HTML(response.body)
      refund_link = html.at_css(%(a[href*="#{new_hotel_folio_transaction_path(hotel, booking)}"][href*="transaction_type=payment"][href*="category=refund"]))
      expect(refund_link).to be_present
      expect(refund_link["data-turbo-frame"]).to eq("offcanvas_drawer")
      expect(refund_link["data-offcanvas-variant"]).to eq("right")
    end

    it "does not show normal actions on an open business date when the user lacks permission" do
      booking = create_booking_with_folio(guest_name: "No Permission Guest", confirmation_token: "BK-NOPERM", folio_number: 607, charges: 100)

      get hotel_folio_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No posting actions available")
      expect(response.body).to include("Generate Report")
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :pdf))
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :csv))
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
      expect(response.body).to include("Generate Report")
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :pdf))
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :csv))
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
      expect(response.body).to include("Generate Report")
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :pdf))
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :csv))
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
      expect(response.body).to include("Generate Report")
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :pdf))
      expect(response.body).to include(ledger_hotel_folio_path(hotel, booking, format: :csv))
      expect(response.body).not_to include("Post Payment")
      expect(response.body).not_to include("Post Charge")
      expect(response.body).not_to include("Post Adjustment")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).to include(reverse_hotel_folio_transaction_path(hotel, booking, transaction))
    end

    it "enables booking invoice report only for completed bookings with closed folios" do
      open_booking = create_booking_with_folio(guest_name: "Open Invoice Guest", confirmation_token: "BK-OPEN-INV", folio_number: 613, charges: 100)
      completed_booking = create_booking_with_folio(guest_name: "Completed Invoice Guest", confirmation_token: "BK-DONE-INV", folio_number: 614, charges: 100, status: "closed", booking_status: "completed")

      get hotel_folio_path(hotel, open_booking)

      open_html = Nokogiri::HTML(response.body)
      expect(open_html.text.squish).to include("Booking Invoices Available after checkout.")
      expect(open_html.at_css(%(a[href="#{invoice_hotel_folio_path(hotel, open_booking, format: :pdf)}"]))).to be_nil

      get hotel_folio_path(hotel, completed_booking)

      completed_html = Nokogiri::HTML(response.body)
      invoice_link = completed_html.at_css(%(a[href="#{invoice_hotel_folio_path(hotel, completed_booking, format: :pdf)}"]))
      expect(invoice_link).to be_present
      expect(invoice_link.text.squish).to eq("Booking Invoices")
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

    it "renders the move forecast action without the fallback dash" do
      %w[
        manage_folio_movements
        post_folio_charges
      ].each { |slug| grant_permission(slug) }
      booking = create_booking_with_folio(guest_name: "Forecast Move Guest", confirmation_token: "BK-MOVE-FC", folio_number: 615, check_out: Date.current + 1.day)
      create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_number: 616)
      create(:folio_forecasted_charge, booking_folio: booking.booking_folio, amount: 30, stay_date: Date.current, charge_kind: "accommodation")

      get hotel_folio_path(hotel, booking)

      html = Nokogiri::HTML(response.body)
      forecast_row = html.css("tr[data-section='forecasted']").find { |row| row.text.include?("Move Forecast") }
      action_cell = forecast_row.css("td").last

      expect(response).to have_http_status(:success)
      expect(action_cell.at_css("button").text.squish).to eq("Move Forecast")
      expect(action_cell.text.squish).not_to include("—")
    end

    it "renders folio windows and switches the active ledger" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "Window Guest", confirmation_token: "BK-WINDOW", folio_number: 617)
      primary_folio = booking.booking_folio
      company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_number: 618)
      create(:folio_transaction, booking_folio: primary_folio, transaction_type: "charge", category: "accommodation", amount: 100, description: "Room Charge")
      create(:folio_transaction, booking_folio: company_folio, transaction_type: "charge", category: "other", amount: 40, description: "Company Charge")

      get hotel_folio_path(hotel, booking, active_folio_id: company_folio.id)

      html = Nokogiri::HTML(response.body)
      folio_windows_frame = html.at_css("turbo-frame#folio_windows_frame")
      active_panel = html.at_css("[data-testid='active-folio-window-panel']")
      ledger = html.at_css("section[data-controller='folio-ledger']").text.squish

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Manage Folio Windows")
      expect(folio_windows_frame).to be_present
      expect(folio_windows_frame["data-turbo-action"]).to eq("advance")
      expect(folio_windows_frame.css("a[data-turbo-frame='folio_windows_frame']").size).to eq(2)
      expect(folio_windows_frame.css("a[data-turbo-action='advance']").size).to eq(2)
      expect(active_panel.text.squish).to include("Company Folio")
      expect(active_panel.text.squish).to include("Folio Name")
      expect(active_panel.text.squish).to include("Default")
      expect(active_panel.text.squish).to include("Additional")
      expect(active_panel.text.squish).to include("Folio Status")
      expect(active_panel.text.squish).to include("Type")
      expect(active_panel.text.squish).to include("Payer")
      expect(active_panel.text.squish).to include("Balance")
      expect(active_panel.css("a, button").map { |element| element.text.squish }).to include("Edit", "Close")
      expect(active_panel.css("a, button").map { |element| element.text.squish }).not_to include("View")
      expect(ledger).to include("Company Charge")
      expect(ledger).not_to include("Room Charge")
    end
  end

  describe "POST /hotel/:hotel_id/folios/:booking_id/windows" do
    it "requires manage_folio_windows permission" do
      booking = create_booking_with_folio(guest_name: "No Windows", confirmation_token: "BK-NOWIN", folio_number: 619)

      expect {
        post windows_hotel_folio_path(hotel, booking), params: {
          booking_folio: { name: "Company Folio", folio_type: "external", payer_type: "company" }
        }
      }.not_to change(BookingFolio, :count)

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
    end

    it "creates a non-primary folio window and logs the operation" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "Window Creator", confirmation_token: "BK-WIN", folio_number: 620)

      expect {
        post windows_hotel_folio_path(hotel, booking), params: {
          booking_folio: { name: "Company Folio", folio_type: "external", payer_type: "company" }
        }
      }.to change { booking.booking_folios.count }.by(1)
        .and change(FolioOperationLog.where(operation_type: "create_folio"), :count).by(1)

      folio = booking.booking_folios.order(:id).last
      expect(folio).not_to be_is_primary
      expect(folio.name).to eq("Company Folio")
      expect(response).to redirect_to(hotel_folio_path(hotel, booking, active_folio_id: folio.id))
    end

    it "creates external folio windows with every supported payer type" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "External Payers", confirmation_token: "BK-PAYERS", folio_number: 627)

      expect {
        %w[guest company agent hotel custom].each do |payer_type|
          post windows_hotel_folio_path(hotel, booking), params: {
            booking_folio: { name: "#{payer_type.humanize} Folio", folio_type: "external", payer_type: payer_type }
          }
        end
      }.to change { booking.booking_folios.count }.by(5)

      expect(booking.booking_folios.order(:id).last(5).map(&:payer_type)).to eq(%w[guest company agent hotel custom])
    end

    it "coerces locked payer types submitted through the controller" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "Locked Payers", confirmation_token: "BK-LOCK", folio_number: 628)

      post windows_hotel_folio_path(hotel, booking), params: {
        booking_folio: { name: "Guest Locked", folio_type: "guest", payer_type: "company" }
      }
      post windows_hotel_folio_path(hotel, booking), params: {
        booking_folio: { name: "House Locked", folio_type: "house", payer_type: "custom" }
      }

      guest_locked, house_locked = booking.booking_folios.order(:id).last(2)
      expect(guest_locked.payer_type).to eq("guest")
      expect(house_locked.payer_type).to eq("hotel")
    end

    it "renders the add folio window form in the right offcanvas" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "Window Sheet", confirmation_token: "BK-SHEET", folio_number: 622)

      get new_window_hotel_folio_path(hotel, booking, origin: "folios")

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(turbo-frame id="offcanvas_drawer"))
      expect(response.body).to include("Add Folio Window")
      expect(response.body).to include("Set this folio as primary")
      expect(response.body).to include("booking_folio[set_folio_as_primary_reason]")
      expect(response.body).to include(%(<option selected="selected" value="external">External</option>))
      expect(response.body).to include(%(<option value="house">House</option>))
      expect(response.body).to include(%(<option value="agent">Agent</option>))
      expect(response.body).to include(%(<option value="hotel">Hotel</option>))
    end

    it "creates a folio as primary when requested with a primary reason" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "Primary Creator", confirmation_token: "BK-PRIMARY", folio_number: 623)
      original_primary = booking.booking_folio

      expect {
        post windows_hotel_folio_path(hotel, booking), params: {
          booking_folio: {
            name: "Company Folio",
            folio_type: "external",
            payer_type: "company",
            is_primary: "1",
            set_folio_as_primary_reason: "Company pays all charges"
          }
        }
      }.to change { booking.booking_folios.count }.by(1)
        .and change(FolioOperationLog.where(operation_type: "set_default_folio"), :count).by(1)

      new_primary = booking.reload.booking_folio
      expect(new_primary.name).to eq("Company Folio")
      expect(original_primary.reload).not_to be_is_primary
      expect(new_primary).to be_is_primary
    end

    it "rejects primary reassignment without the primary reason" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "Reason Required", confirmation_token: "BK-REASON", folio_number: 624)

      expect {
        post windows_hotel_folio_path(hotel, booking), params: {
          booking_folio: { name: "Company Folio", folio_type: "external", payer_type: "company", is_primary: "1" }
        }
      }.not_to change(BookingFolio, :count)

      expect(flash[:alert]).to include("Reason for setting primary folio")
    end

    it "edits, closes, and reopens folio windows with operation logs" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "Window Ops", confirmation_token: "BK-WINOPS", folio_number: 621, charges: 100, payments: 100)
      folio = booking.booking_folio

      get edit_window_hotel_folio_path(hotel, booking, folio)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Edit Folio Window")
      expect(response.body).to include("Save Changes")

      expect {
        patch window_hotel_folio_path(hotel, booking, folio), params: {
          booking_folio: { name: "Guest Main", reason: "Clarify payer" }
        }
      }.to change(FolioOperationLog.where(operation_type: "rename_folio"), :count).by(1)

      expect(folio.reload.name).to eq("Guest Main")

      expect {
        post close_window_hotel_folio_path(hotel, booking, folio), params: {
          booking_folio: { reason: "Settled" }
        }
      }.to change(FolioOperationLog.where(operation_type: "close_folio"), :count).by(1)

      expect(folio.reload).to be_closed

      expect {
        post reopen_window_hotel_folio_path(hotel, booking, folio), params: {
          booking_folio: { reason: "Correction needed" }
        }
      }.to change(FolioOperationLog.where(operation_type: "reopen_folio"), :count).by(1)

      expect(folio.reload).to be_open
      expect(response).to redirect_to(hotel_folio_path(hotel, booking, active_folio_id: folio.id))
    end

    it "sets an existing secondary folio as primary from the edit form" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "Default Switch", confirmation_token: "BK-SWITCH", folio_number: 625)
      original_primary = booking.booking_folio
      secondary = create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_number: 626)

      expect {
        patch window_hotel_folio_path(hotel, booking, secondary), params: {
          booking_folio: {
            name: "Company Folio",
            folio_type: "external",
            payer_type: "company",
            is_primary: "1",
            set_folio_as_primary_reason: "Company is now responsible"
          }
        }
      }.to change(FolioOperationLog.where(operation_type: "set_default_folio"), :count).by(1)

      expect(secondary.reload).to be_is_primary
      expect(original_primary.reload).not_to be_is_primary
      expect(booking.reload.booking_folio).to eq(secondary)
    end
  end

  describe "GET /hotel/:hotel_id/folios/:booking_id/invoice" do
    it "returns a PDF for a closed folio" do
      booking = create_booking_with_folio(guest_name: "Invoice Guest", confirmation_token: "BK-PDF", folio_number: 611, charges: 100, status: "closed")

      get invoice_hotel_folio_path(hotel, booking, format: :pdf)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("inline")
    end

    it "redirects when the folio is open" do
      booking = create_booking_with_folio(guest_name: "Open Guest", confirmation_token: "BK-OPEN", folio_number: 612, charges: 100)

      get invoice_hotel_folio_path(hotel, booking, format: :pdf)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Folio invoice is only available for checked-out bookings with a closed folio.")
    end
  end

  describe "GET /hotel/:hotel_id/folios/:booking_id/ledger" do
    it "downloads a CSV for the current folio" do
      booking = create_booking_with_folio(guest_name: "Ledger Export Guest", confirmation_token: "BK-LEDGER-CSV", room_number: "804", folio_number: 615, charges: 125)

      get ledger_hotel_folio_path(hotel, booking, format: :csv)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")
      expect(response.headers["Content-Disposition"]).to include("folio-ledger")
      expect(response.body).to include("Booking Ref,Guest Name")
      expect(response.body).to include("BK-LEDGER-CSV")
      expect(response.body).to include("Ledger Export Guest")
      expect(response.body).to include("804")
      expect(response.body).to include("125.0")
    end

    it "renders a PDF for the current folio" do
      booking = create_booking_with_folio(guest_name: "Ledger Export PDF Guest", confirmation_token: "BK-LEDGER-PDF", room_number: "805", folio_number: 616, charges: 135)

      get ledger_hotel_folio_path(hotel, booking, format: :pdf)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("inline")
      expect(response.headers["Content-Disposition"]).to include("folio-ledger")
      expect(response.body.dup.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
    end

    it "redirects when the booking has no folio" do
      booking = create(:booking, hotel: hotel)

      get ledger_hotel_folio_path(hotel, booking, format: :csv)

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))
      expect(flash[:alert]).to eq("Booking has no folio.")
    end
  end

  def grant_permission(slug)
    permission = Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    role.permissions << permission unless role.permissions.exists?(permission.id)
  end

  def create_booking_with_folio(guest_name:, confirmation_token:, folio_number:, room_number: nil, charges: 0, payments: 0, adjustments: 0, status: "open", booking_status: "confirmed", check_in: Date.current, check_out: Date.current)
    room_type = create(:room_type, hotel: hotel)
    booking = create(
      :booking,
      hotel: hotel,
      status: booking_status,
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
