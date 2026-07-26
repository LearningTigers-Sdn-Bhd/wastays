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

  def booking_details_path(booking, **params)
    hotel_booking_workspace_path(hotel, booking, { tab: "booking_details" }.merge(params))
  end

  def folio_operations_path(booking, folio_id: nil, **params)
    query = { tab: "folio_operations" }.merge(params)
    query[:folio_id] = folio_id if folio_id.present?
    hotel_booking_workspace_path(hotel, booking, query)
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
      expect(response.body).to include("Guest / Booking")
      expect(response.body).to include("Folio Reference")
      expect(response.body).to include("Stay / Room")
      expect(response.body).to include("Financials")
      expect(response.body).to include("Status")
      expect(response.body).to include("Action")
      expect(response.body).to include("sticky right-0")
      expect(response.body).to include("View Folio")
      expect(response.body).to include("View Booking")
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: booking.booking_folio.id)))
      expect(response.body).to include(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(response.body).to include("MYR 120.00")
      expect(response.body).to include("Balance Due")
      expect(response.body).to include("data-controller=\"dropdown\"")
      expect(response.body).to include("More actions for Amir Hakim")
      expect(response.body).to include("border-emerald-200 bg-emerald-50 text-emerald-700")
      expect(response.body).to include("text-red-700")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).not_to include("Add Payment")
      expect(response.body).not_to include("Add Charge")
      expect(response.body).not_to include("Adjustment")
      expect(response.body).not_to include("Booking &rsaquo;")
      expect(response.body).not_to include("type=\"submit\" class=\"inline-flex items-center justify-center rounded-lg bg-primary")
    end

    it "links View Folio directly to the workspace folio context" do
      booking = create_booking_with_folio(guest_name: "Amir Hakim", confirmation_token: "BK-8891", folio_number: 232, charges: 120)

      get hotel_folios_path(hotel)

      expect(response.body).to include(%(href="#{CGI.escapeHTML(hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: booking.booking_folio.id))}"))
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
      expect(results_text).to include("MYR 80.00")
      expect(results_text).to include("Refund Due")
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

    it "does not sync the Needs Attention summary count with table search or filters" do
      create_booking_with_folio(guest_name: "Attention Guest", confirmation_token: "BK-ATT", folio_number: 351, charges: 200)
      create_booking_with_folio(guest_name: "Settled Guest", confirmation_token: "BK-SET", folio_number: 352, charges: 100, payments: 100)

      get hotel_folios_path(hotel), params: { query: "Settled" }

      expect(response.body).to include("1 folio needs attention")
      expect(results_text).to include("Settled Guest")
      expect(results_text).not_to include("Attention Guest")
    end

    it "shows a Needs Attention summary with a link to the standalone review page" do
      create_booking_with_folio(guest_name: "Amir Hakim", confirmation_token: "BK-8891", folio_number: 401, charges: 120)
      create_booking_with_folio(guest_name: "Nur Aina", confirmation_token: "BK-8893", folio_number: 402, payments: 80)
      create_booking_with_folio(guest_name: "Settled Guest", confirmation_token: "BK-8899", folio_number: 404, charges: 100, payments: 100)

      get hotel_folios_path(hotel)

      document = Nokogiri::HTML(response.body)

      expect(response.body).to include("Needs Attention")
      expect(response.body).to include("2 folios need attention")
      expect(document.at_css("a[href='#{needs_attention_hotel_folios_path(hotel)}']")).to be_present
    end

    it "shows a clear state when nothing needs attention" do
      create_booking_with_folio(guest_name: "Settled Guest", confirmation_token: "BK-8900", folio_number: 405, charges: 100, payments: 100)

      get hotel_folios_path(hotel)

      expect(response.body).to include("No folios need attention")
      expect(response.body).not_to include("Review Needs Attention")
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

  describe "GET /hotel/:hotel_id/folios/needs-attention" do
    it "lists only folios that need attention, including unsynced completed refunds" do
      balance_due = create_booking_with_folio(guest_name: "Amir Hakim", confirmation_token: "BK-8891", folio_number: 401, charges: 120)
      refund_due = create_booking_with_folio(guest_name: "Nur Aina", confirmation_token: "BK-8893", folio_number: 402, payments: 80)
      unsynced = create_booking_with_folio(guest_name: "Daniel Lim", confirmation_token: "BK-8898", folio_number: 403, charges: 100, payments: 100)
      create(:refund_request, booking: unsynced, status: "completed", refund_amount: 45)
      settled = create_booking_with_folio(guest_name: "Settled Guest", confirmation_token: "BK-8899", folio_number: 404, charges: 100, payments: 100)

      get needs_attention_hotel_folios_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Needs Attention")
      expect(results_text).to include(balance_due.guest_name)
      expect(results_text).to include("Balance Due")
      expect(results_text).to include(refund_due.guest_name)
      expect(results_text).to include("Refund Due")
      expect(results_text).to include(unsynced.guest_name)
      expect(results_text).not_to include(settled.guest_name)
    end

    it "supports its own search and filters, independent of the main folios list" do
      balance_due = create_booking_with_folio(guest_name: "Amir Hakim", confirmation_token: "BK-8891", folio_number: 406, charges: 120)
      refund_due = create_booking_with_folio(guest_name: "Nur Aina", confirmation_token: "BK-8893", folio_number: 407, payments: 80)

      get needs_attention_hotel_folios_path(hotel), params: { query: "Amir" }
      expect(results_text).to include(balance_due.guest_name)
      expect(results_text).not_to include(refund_due.guest_name)

      get needs_attention_hotel_folios_path(hotel), params: { filter: "refund_due" }
      expect(results_text).to include(refund_due.guest_name)
      expect(results_text).not_to include(balance_due.guest_name)
    end

    it "requires view booking permission" do
      role.permissions.delete(view_bookings)

      get needs_attention_hotel_folios_path(hotel)

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
    end
  end

  describe "GET /hotel/:hotel_id/folios/:booking_id" do
    it "uses booking navigation by default" do
      booking = create_booking_with_folio(guest_name: "Booking Origin", confirmation_token: "BK-BOOK", folio_number: 601, charges: 100)

      get folio_operations_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Reservations")
      expect(Nokogiri::HTML(response.body).at_css("a[aria-label='Back to Reservations']")&.[]("href")).to eq(hotel_front_desk_path(hotel, tab: "bookings", view: "list"))
      expect(response.body).to include(%(href="#{booking_details_path(booking)}"))
      expect(response.body).to include('id="folio-operations-panel"')
      expect(response.body).not_to include("Back to Booking")
      expect(response.body).not_to include("Back to All Folios")
    end

    it "uses folios navigation when opened from the folios index" do
      booking = create_booking_with_folio(guest_name: "Folio Origin", confirmation_token: "BK-FOLIO", folio_number: 602, charges: 100)

      get folio_operations_path(booking, origin: "folios")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="booking-workspace"')
      expect(response.body).to include("Folios")
      expect(response.body).to include(%(href="#{folio_operations_path(booking)}"))
      expect(response.body).to include('id="folio-operations-panel"')
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

      get folio_operations_path(booking)

      body = response.body

      expect(response).to have_http_status(:success)
      expect(body).to include('id="folio-operations-panel"')
      expect(body).to include('data-testid="booking-workspace"')
      expect(body).to include(booking.booking_folio.folio_reference_display)
      expect(body).to include(%(href="#{booking_details_path(booking)}"))
      expect(body).not_to include("Go to Booking")
      expect(body).not_to include("Close Folio")
    end

    it "renders blocked checkout status with blocker summary" do
      booking = create_booking_with_folio(guest_name: "Blocked Guest", confirmation_token: "BK-BLOCK", folio_number: 605, charges: 100, check_out: Date.current + 1.day)
      create(:folio_forecasted_charge, booking_folio: booking.booking_folio, amount: 30, stay_date: Date.current, charge_kind: "accommodation")

      get folio_operations_path(booking)

      body = response.body

      expect(response).to have_http_status(:success)
      expect(body).to include('id="folio-operations-panel"')
      expect(body).to include("MYR 130.00")
      expect(body).to include(%(href="#{booking_details_path(booking)}"))
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

      get folio_operations_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Add Payment")
      expect(response.body).to include("Add Charge")
      expect(response.body).to include("Add Adjustment")
      expect(response.body).to include("Ledger Actions")
      expect(response.body).to include('id="folio-operations-panel"')
      expect(response.body).to include("Folios")
      expect(response.body).to include("More Actions")
      expect(response.body).to include("Issue Refund")

      html = Nokogiri::HTML(response.body)
      refund_link = html.at_css(%(a[href*="#{hotel_folio_action_post_transaction_path(hotel, booking)}"][href*="transaction_type=payment"][href*="category=refund"]))
      expect(refund_link).to be_present
      expect(refund_link["data-turbo-frame"]).to eq("folio_action_sheet")
    end

    it "does not show normal actions on an open business date when the user lacks permission" do
      booking = create_booking_with_folio(guest_name: "No Permission Guest", confirmation_token: "BK-NOPERM", folio_number: 607, charges: 100)

      get folio_operations_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No posting actions available")
      expect(response.body).to include('id="folio-operations-panel"')
      expect(response.body).to include("Folios")
      expect(response.body).not_to include("Add Payment")
      expect(response.body).not_to include("Add Charge")
      expect(response.body).not_to include("Add Adjustment")
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

      get folio_operations_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Financial posting is temporarily unavailable.")
      expect(response.body).to include('id="folio-operations-panel"')
      expect(response.body).to include("Folios")
      expect(response.body).to include("Night audit is currently running for this business date.")
      expect(response.body).to include("View Night Audit")
      expect(response.body).to include(hotel_night_audit_path(hotel, night_audit))
      expect(response.body).not_to include("Add Payment")
      expect(response.body).not_to include("Add Charge")
      expect(response.body).not_to include("Add Adjustment")
      expect(response.body).not_to include("More Actions")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).not_to include(hotel_folio_action_reverse_transaction_path(hotel, booking, transaction))
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

      get folio_operations_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Normal folio posting is blocked.")
      expect(response.body).to include('id="folio-operations-panel"')
      expect(response.body).to include("Folios")
      expect(response.body).to include("Night audit is blocked. Resolve blockers from the Night Audit page, then retry audit.")
      expect(response.body).to include("View Night Audit Blockers")
      expect(response.body).to include(resolve_hotel_night_audit_path(hotel, night_audit))
      expect(response.body).not_to include("Add Payment")
      expect(response.body).not_to include("Add Charge")
      expect(response.body).not_to include("Add Adjustment")
      expect(response.body).not_to include("More Actions")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).not_to include(hotel_folio_action_reverse_transaction_path(hotel, booking, transaction))
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

      get folio_operations_path(booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Normal posting actions are unavailable for a closed folio.")
      expect(response.body).to include('id="folio-operations-panel"')
      expect(response.body).to include("Folios")
      expect(response.body).not_to include("Add Payment")
      expect(response.body).not_to include("Add Charge")
      expect(response.body).not_to include("Add Adjustment")
      expect(response.body).not_to include("Issue Refund")
      expect(response.body).to include(hotel_folio_action_reverse_transaction_path(hotel, booking, transaction))
    end

    it "enables booking invoice report only for completed bookings with closed folios" do
      open_booking = create_booking_with_folio(guest_name: "Open Invoice Guest", confirmation_token: "BK-OPEN-INV", folio_number: 613, charges: 100)
      completed_booking = create_booking_with_folio(guest_name: "Completed Invoice Guest", confirmation_token: "BK-DONE-INV", folio_number: 614, charges: 100, status: "closed", booking_status: "completed")

      get folio_operations_path(open_booking)

      open_html = Nokogiri::HTML(response.body)
      expect(open_html.at_css('[data-testid="booking-workspace"]')).to be_present
      expect(open_html.at_css(%(a[href="#{invoice_hotel_folio_path(hotel, open_booking, format: :pdf)}"]))).to be_nil

      get folio_operations_path(completed_booking)

      completed_html = Nokogiri::HTML(response.body)
      expect(completed_html.at_css('[data-testid="booking-workspace"]')).to be_present
    end

    it "renders one horizontal ledger table with an Outstanding total and no collapse control" do
      booking = create_booking_with_folio(guest_name: "Ledger Guest", confirmation_token: "BK-LEDGER", folio_number: 603, charges: 100, payments: 40)

      get folio_operations_path(booking)

      html = Nokogiri::HTML(response.body)
      ledger = html.at_css("section[data-testid='folio-ledger']")
      headers = ledger.css("thead th").map { |header| header.text.squish }

      expect(response).to have_http_status(:success)
      expect(ledger.at_css("table.panel-table")).to be_present
      expect(headers).to eq([ "Date", "Code", "Description", "Debit (MYR)", "Credit (MYR)", "Actions" ])
      expect(ledger.text.squish).to include("Outstanding MYR 60.00")
      expect(ledger.text.squish).not_to include("Posted balance")
      expect(ledger.at_css('[data-folio-ledger-section-param="forecasted"]')).to be_nil
    end

    it "renders folio windows and switches the active ledger" do
      grant_permission("manage_folio_windows")
      booking = create_booking_with_folio(guest_name: "Window Guest", confirmation_token: "BK-WINDOW", folio_number: 617)
      primary_folio = booking.booking_folio
      company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_number: 618)
      create(:folio_transaction, booking_folio: primary_folio, transaction_type: "charge", category: "accommodation", amount: 100, description: "Room Charge")
      create(:folio_transaction, booking_folio: company_folio, transaction_type: "charge", category: "other", amount: 40, description: "Company Charge")

      get folio_operations_path(booking, folio_id: company_folio.id)

      html = Nokogiri::HTML(response.body)
      folio_windows_frame = html.at_css("turbo-frame#folio_windows_frame")
      active_panel = html.at_css("[data-testid='active-folio-window-panel']")
      ledger = html.at_css("section[data-testid='folio-ledger']").text.squish

      expect(response).to have_http_status(:success)
      expect(response.body).to include('id="folio-operations-panel"')
      expect(response.body).to include('data-testid="booking-workspace"')
      expect(response.body).to include(company_folio.folio_reference_display)
      expect(ledger).to include("Company Charge")
      expect(ledger).not_to include("Room Charge")
    end

    it "renders top-level folio tabs and updates breadcrumbs for the active tab" do
      booking = create_booking_with_folio(guest_name: "Tabbed Guest", confirmation_token: "BK-TABS", folio_number: 629)

      get folio_operations_path(booking)

      html = Nokogiri::HTML(response.body)
      tabs = html.at_css("[data-testid='folio-tabs']")
      breadcrumb_tab = html.at_css("[data-tabs-breadcrumb-label]")

      expect(response).to have_http_status(:success)
      expect(html.at_css('[data-testid="booking-workspace"]')).to be_present
      expect(response.body).to include("Folios")
    end

    it "keeps folio window subtabs inside the ledger panel only" do
      booking = create_booking_with_folio(guest_name: "Subtab Guest", confirmation_token: "BK-SUBTAB", folio_number: 630)
      create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_number: 631)

      get folio_operations_path(booking)

      html = Nokogiri::HTML(response.body)
      ledger_panel = html.at_css("[data-testid='folio-ledger-panel']")
      billing_panel = html.at_css("[data-testid='folio-billing-instructions-panel']")

      expect(html.at_css('[data-testid="booking-workspace"]')).to be_present
      expect(response.body).to include(booking.booking_folio.folio_reference_display)
    end

    it "renders billing instructions, route preview, and activity log panels" do
      grant_permission("manage_folio_movements")
      booking = create_booking_with_folio(guest_name: "Panels Guest", confirmation_token: "BK-PANELS", folio_number: 632)
      company_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, folio_number: 633, label: "Company Folio")
      code = create(:transaction_code, hotel: hotel, code: "FNB-P", name: "Food and Beverage", category: "fb")
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: code, target_folio: company_folio)
      create(:folio_operation_log, hotel: hotel, booking: booking, actor: user, operation_type: "create_routing_rule", target_folio: company_folio, metadata: { "transaction_code_code" => "FNB-P" })

      get folio_operations_path(booking)

      body = response.body

      expect(response).to have_http_status(:success)
      expect(body).to include('data-testid="booking-workspace"')
      expect(body).to include("Folios")
    end

    it "renders attached taxes and fees as clickable nested billing instruction rows" do
      grant_permission("manage_folio_movements")
      booking = create_booking_with_folio(guest_name: "Nested Taxes Guest", confirmation_token: "BK-NESTED-#{SecureRandom.uuid}", folio_number: 640)
      hotel.update!(sst_enabled: true)
      Financials::EnsureDefaultTransactionCodes.call(hotel)
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")

      get folio_operations_path(booking)

      html = Nokogiri::HTML(response.body)
      expect(html.at_css('[data-testid="booking-workspace"]')).to be_present
      expect(response.body).to include("Folios")
      expect(room_code.transaction_code_taxes).to exist
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

      expect(response).to redirect_to(folio_operations_path(booking))
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

      expect(response).to redirect_to(folio_operations_path(booking))
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
      guest_email: "#{guest_name.parameterize}@example.com",
      guest_phone: "9999999999",
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
