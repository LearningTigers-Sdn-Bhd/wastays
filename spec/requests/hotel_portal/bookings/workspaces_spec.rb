# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Workspaces", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_bookings) { Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View Bookings" } }
  let(:manage_bookings) { Permission.find_or_create_by!(slug: "manage_bookings") { |permission| permission.name = "Manage Bookings" } }
  let(:manage_folio_windows) { Permission.find_or_create_by!(slug: "manage_folio_windows") { |permission| permission.name = "Manage Folio Windows" } }
  let(:manage_folio_movements) { Permission.find_or_create_by!(slug: "manage_folio_movements") { |permission| permission.name = "Manage Folio Movements" } }
  let(:audit_feature) { create(:feature, feature_group: create(:feature_group), slug: "full_audit_trail") }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      confirmation_token: "BK-PANEL-42",
      reservation_number: 42,
      guest_name: "Fallback Name",
      source: "direct"
    )
  end

  before do
    role.permissions << view_bookings
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/bookings/:booking_id/workspace" do
    describe "tourism tax voucher entry in folio actions" do
      before do
        role.permissions << manage_bookings
        create(:booking_folio, booking: booking, hotel: hotel)
      end

      it "shows active link when booking owes tourism tax" do
        booking.update!(guest_country: "Singapore", tourism_tax_amount: 20.0, tax_lines: [ { "type" => "tourism_tax", "amount" => 20.0 } ])

        get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Issue Tourism Tax Voucher")
        expect(response.body).to include(issue_hotel_booking_tourism_tax_voucher_path(hotel, booking))
      end

      it "omits entry when booking has no tourism tax" do
        get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include("Tourism Tax Voucher")
      end
    end

    it "renders plain booking, guest, stay, source, and room details" do
      guest = create(:guest, name: "Aina Rahman")
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")

      get hotel_booking_workspace_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Booking workspace")
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include(booking.formatted_reservation_number)
      expect(response.body).to include(booking.formatted_receipt_number)
      expect(response.body).to include("Aina Rahman")
      expect(response.body).to include("Garden Suite")
      expect(response.body).to include("208")
      expect(response.body).to include(booking.check_in.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"))
      expect(response.body).to include(booking.check_out.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"))
      expect(response.body).to include('data-testid="booking-workspace-header"')
    end

    it "labels the overview references section and demotes the confirmation code" do
      booking.update!(
        source: "booking_com",
        external_reference: "EXT-#{'LONG-' * 20}",
        channel_manager_reference: "CHANNEL-REFERENCE-42"
      )
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Aina Rahman"), is_primary: true)

      get hotel_booking_workspace_path(hotel, booking)

      overview = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="booking-overview-heading"]')
      expect(overview.text).to include("References")
      expect(overview.text).not_to include("Identifiers")
      expect(overview.text).to include("Confirmation code")
      expect(overview.text).to include("Source", "Booking Com", booking.external_reference, "CHANNEL-REFERENCE-42")
      expect(overview.at_xpath(".//dt[normalize-space()='External Reference']/following-sibling::dd")["class"]).to include("break-all")

      get hotel_booking_workspace_path(hotel, booking, tab: "source_details")

      legacy_source_details = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="source-details-heading"]')
      expect(legacy_source_details.text).to include("Booking Com", booking.external_reference, "CHANNEL-REFERENCE-42")
    end

    it "uses the operational booking number in the breadcrumb" do
      get hotel_booking_workspace_path(hotel, booking)

      breadcrumb = Nokogiri::HTML(response.body).at_css("#hotel-breadcrumb")
      expect(breadcrumb.text).to include(booking.formatted_reservation_number)
      expect(breadcrumb.text).not_to include(booking.confirmation_token)
    end

    it "renders explicit rate, source, and deposit form states" do
      create(:booking_room, booking: booking, nightly_rate_snapshot: {})

      get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
      room_rate_table = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="room-rate-heading"] table')
      expect(room_rate_table.text).to include("Stay Date", "Room Type", "Room", "Rate Plan", "Nightly Rate", "Rate unavailable")
      expect(room_rate_table.text).not_to include("MYR 0.00", "Posted to folio", "Check-in", "Occupancy", "Status")
      expect(response.body).not_to include("Nightly Rate Schedule")

      get hotel_booking_workspace_path(hotel, booking, tab: "source_details")
      expect(response.body).to include("Not provided")

      get hotel_booking_workspace_path(hotel, booking, tab: "security_deposits")
      expect(response.body).to include("border border-border-interactive bg-card")
      expect(response.body).to include("No held deposit is available to release")

      get hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests")
      expect(response.body).to include('class="flex h-full min-h-0 flex-col"')
      expect(response.body).to include("grid min-h-0 flex-1")
    end

    it "renders a full-width standalone Overview without context controls" do
      room_type = create(:room_type, hotel: hotel, name: "Executive Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")

      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('[data-layout-mode="standard"]')).to be_present
      expect(document.at_css('[data-testid="workspace-entity-rail"]')).to be_nil
      expect(document.at_xpath('//button[normalize-space()="Change Context"]')).to be_nil
      expect(document.at_css("#booking-entity-selector-sheet")).to be_nil
      expect(document.css("h1").size).to eq(1)
      expect(document.at_css("main h2").text).to eq("Overview")
    end

    it "keeps Change Billing Routes in the standalone Billing heading" do
      role.permissions << manage_folio_movements
      create(:booking_room, booking: booking, room_number: "208")

      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      billing_action = document.at_xpath("//main//a[normalize-space()='Change Billing Routes']")
      expect(document.at_css("main h2").text).to eq("Billing")
      expect(billing_action).to be_present
      expect(document.at_css('[data-testid="workspace-entity-rail"]')).to be_nil
    end

    it "shows Billing Routes to superadmins and hides them from unauthorized staff" do
      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")
      expect(Nokogiri::HTML(response.body).at_xpath("//main//a[normalize-space()='Change Billing Routes']")).to be_nil

      sign_in_as(create(:user, :superadmin))
      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")

      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).at_xpath("//main//a[normalize-space()='Change Billing Routes']")).to be_present
    end

    it "shows recorded rates even when booking dates are invalid" do
      booking.update!(check_in: Time.zone.local(2026, 6, 30, 15), check_out: Time.zone.local(2026, 6, 30, 12))
      room_type = create(:room_type, hotel: hotel, name: "Garden Prestige Suite")
      rate_plan = create(:rate_plan, room_type: room_type, name: "Standard Rate")
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan, room_number: "107", nightly_rate_snapshot: { "2026-06-30" => { "price" => "740.0" } })

      get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("30 Jun 2026", "Garden Prestige Suite", "107", "Standard Rate", "MYR 740.00")
      expect(response.body).not_to include("Booking dates need review", "Stay dates do not produce any room nights")
    end

    it "consolidates folio, transaction, and billing rule content into the control panel" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "PRIVATE FOLIO MARKER")
      create(:folio_transaction, booking_folio: folio, description: "PRIVATE TRANSACTION MARKER")
      transaction_code = create(:transaction_code, hotel: hotel)
      target_folio = create(:booking_folio, booking: booking, hotel: hotel, name: "PRIVATE ROUTE MARKER", is_primary: false)
      create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: transaction_code, target_folio: target_folio)

      get hotel_booking_workspace_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Folios")
      expect(response.body).to include("Billing")
      expect(response.body).not_to include("PRIVATE FOLIO MARKER")

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("PRIVATE FOLIO MARKER")
      expect(response.body).to include("PRIVATE TRANSACTION MARKER")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('nav[aria-label="Folio operation sections"]')).to be_nil
      expect(response.body).not_to include("Activity Log")
      expect(document.at_css('[data-folio-ledger-section-param="forecasted"]')["aria-expanded"]).to eq("false")
      expect(document.css("tr[data-section='posted']").all? { |row| !row["class"].to_s.split.include?("hidden") }).to be(true)
      expect(document.css("tr[data-section='forecasted']").all? { |row| row["class"].to_s.split.include?("hidden") }).to be(true)

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id, folio_tab: "activity")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("PRIVATE TRANSACTION MARKER")
      expect(response.body).not_to include("Activity Log")

      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences", folio_id: target_folio.id)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("PRIVATE ROUTE MARKER", "Advanced Billing Rules", "Billing Instructions")
    end

    it "renders standalone billing preferences from billing parties" do
      guest = create(:guest, name: "Aina Rahman")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      corporate_account = create(:account, :corporate, name: "Acme Engineering")
      hotel_corporate_account = create(:hotel_corporate_account, :direct_bill, hotel: hotel, corporate_account: corporate_account)
      company_party = create(:booking_billing_party, :company, booking: booking, hotel: hotel, hotel_corporate_account: hotel_corporate_account)
      create(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: company_party, hotel_corporate_account: hotel_corporate_account, name: "Corporate Folio")

      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Billing parties")
      expect(response.body).to include("Aina Rahman")
      expect(response.body).to include("Primary guest")
      expect(response.body).to include("Acme Engineering")
      expect(response.body).to include("City Ledger · Direct bill enabled")
      expect(response.body).to include("Corporate Folio")
      expect(response.body).not_to include("Advanced Billing Rules", "Billing Instructions")
    end

    it "renders booking-local billing parties for a child booking" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2)

      guest = create(:guest, name: "Child Booking Guest")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      account = create(:hotel_corporate_account, :direct_bill, hotel: hotel)
      company_party = create(:booking_billing_party, :company, booking: booking, hotel: hotel, hotel_corporate_account: account)
      create(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: company_party,
        hotel_corporate_account: account, name: "Child Corporate Folio")

      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      text = document.text
      expect(text).to include("Billing parties", "Child Booking Guest", account.corporate_account.name,
        "Child Corporate Folio", "+ Add billing party", "Edit terms")
      expect(text).not_to include("Booking-local billing exception", "Group accommodation payer")
    end

    it "renders billing-party creation inline without an offcanvas target" do
      corporate_account = create(:account, :corporate, name: "Inline Company")
      create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_account)

      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences", billing_editor: "new_party")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Add billing party", "Inline Company", "Settlement type")
      document = Nokogiri::HTML(response.body)
      form = document.at_css("form[action*='add_billing_party']")
      expect(form).to be_present
      expect(form["data-turbo-frame"]).not_to eq("offcanvas_drawer")
    end

    it "renders flat standalone folio and guest rails" do
      guest = create(:guest, name: "Rail Guest Name")
      booking_guest = create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)

      folio_document = Nokogiri::HTML(response.body)
      folio_nav = folio_document.at_css('nav[aria-label="Booking folios"]')
      expect(folio_nav.at_css("details")).to be_nil
      selected_folio = folio_nav.at_css('a[aria-current="page"]')
      expect(selected_folio.text).to include(folio.display_name, "Open", "MYR 0.00", "Selected:")
      folio_trigger = folio_document.at_css('button[command="show-modal"][commandfor="booking-entity-selector-sheet"]')
      expect(folio_trigger.text.squish).to eq("Choose Folio")
      expect(folio_document.at_css("#booking-entity-selector-sheet-title").text).to eq("Choose Folio")
      expect(folio_document.at_xpath('//button[normalize-space()="Change Context"]')).to be_nil

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id)

      guest_document = Nokogiri::HTML(response.body)
      guest_nav = guest_document.at_css('nav[aria-label="Booking guests"]')
      expect(guest_nav.at_css("details")).to be_nil
      selected_guest = guest_nav.at_css('a[aria-current="page"]')
      expect(selected_guest.text).to include(guest.name, "Primary guest", "Selected:")
      guest_trigger = guest_document.at_css('button[command="show-modal"][commandfor="booking-entity-selector-sheet"]')
      expect(guest_trigger.text.squish).to eq("Choose Guest")
      expect(guest_document.at_css("#booking-entity-selector-sheet-title").text).to eq("Choose Guest")
    end

    it "renders one flat guest group per child booking with exact selected context" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking_room, booking: booking, room_number: "101")
      primary_guest = create(:booking_guest, booking: booking, guest: create(:guest, name: "Room 101 Guest"), is_primary: true)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_room, booking: sibling, room_number: "102")
      create(:booking_guest, booking: sibling, guest: create(:guest, name: "Room 102 Guest"), is_primary: true)

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: primary_guest.id)

      document = Nokogiri::HTML(response.body)
      nav = document.at_css('[data-testid="workspace-entity-rail"] nav[aria-label="Booking guests"]')
      expect(nav.css("section").size).to eq(2)
      expect(nav.css("h3").map { |heading| heading.text.squish }).to eq([ "Room 101", "Room 102" ])
      expect(nav.css("details")).to be_empty
      expect(nav.text).not_to include("All Guests", booking.status.humanize)
      expect(nav.text).not_to include(booking.formatted_reservation_number)
      expect(nav.at_css('a[aria-current="page"]').text).to include("Room 101 Guest", "Primary guest")
      expect(document.css("[id$='-guest-group-#{booking.id}']").map { |node| node["id"] }).to contain_exactly(
        "desktop-guest-group-#{booking.id}",
        "mobile-guest-group-#{booking.id}"
      )
      expect(document.at_css("#guest-details-panel")).to be_present
    end

    it "renders Add Folio in the folio left rail using the workspace flow" do
      role.permissions << manage_folio_windows
      create(:booking_guest, booking: booking, is_primary: true)
      create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")

      document = Nokogiri::HTML(response.body)
      add_folio = document.at_xpath("//a[starts-with(normalize-space(), '+ Add folio')]")
      expect(add_folio).to be_present
      expect(add_folio["href"]).to eq(new_folio_window_hotel_booking_workspace_path(hotel, booking))
      expect(add_folio["href"]).not_to eq(new_window_hotel_folio_path(hotel, booking))
      expect(add_folio["data-turbo-frame"]).to eq("offcanvas_drawer")
    end

    it "renders an actionable guest empty state" do
      role.permissions << manage_bookings

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("main").text).to include("No guest is linked to this booking")
      add_guest = document.at_xpath("//main//a[normalize-space()='Add Guest']")
      expect(add_guest["href"]).to include(hotel_booking_action_manage_guest_path(hotel, booking), "mode=add")
      expect(add_guest["data-turbo-frame"]).to eq("booking_action_sheet")
    end

    it "keeps folio tree links free of obsolete subtab state" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_tab: "forecast")

      document = Nokogiri::HTML(response.body)
      folio_link = document.at_css("nav[aria-label='Booking folios'] a[href*='folio_id=#{folio.id}']")
      expect(folio_link).to be_present
      expect(folio_link["href"]).not_to include("folio_tab")
    end

    it "renders one flat folio group per child booking" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "COLLAPSED-SIBLING")
      sibling.update_column(:status, "checkout_required")
      create(:booking_room, booking: booking, room_number: "101")
      create(:booking_room, booking: sibling, room_number: "102")
      create(:booking_folio, booking: booking, hotel: hotel, name: "Current Folio")
      create(:booking_folio, booking: sibling, hotel: hotel, name: "Sibling Folio")

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      nav = document.at_css('nav[aria-label="Booking folios"]')
      groups = nav.css("section")
      expect(groups.size).to eq(2)
      expect(groups.first.at_css("h3").text.squish).to eq("Room 101")
      expect(groups.last.at_css("h3").text.squish).to eq("Room 102")
      expect(nav.text).not_to include(booking.formatted_reservation_number, sibling.formatted_reservation_number)
      expect(nav.css("details")).to be_empty
      expect(nav.text).not_to include("In house", "Checkout due", booking.guest_name, sibling.guest_name)
      current_folio_link = groups.first.at_css('a[href*="folio_id="]')
      expect(current_folio_link["data-turbo-frame"]).to eq("_top")
    end

    it "marks the selected grouped folio accessibly without a collapsible controller" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_room, booking: booking, room_number: "101")
      create(:booking_room, booking: sibling, room_number: "102")
      create(:booking_folio, booking: booking, hotel: hotel)
      create(:booking_folio, booking: sibling, hotel: hotel)

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")

      document = Nokogiri::HTML(response.body)
      nav = document.at_css('nav[aria-label="Booking folios"]')
      expect(nav.at_css('a[aria-current="page"]')).to be_present
      expect(nav["data-controller"]).to be_nil
      expect(nav.css("details")).to be_empty
    end

    it "does not allow access to another hotel's booking" do
      other_booking = create(:booking, hotel: other_hotel)

      get hotel_booking_workspace_path(hotel, other_booking)

      expect(response).to have_http_status(:not_found)
    end

    it "renders every control panel tab with its declared layout" do
      hotel.update!(plan: create(:plan))
      create(:plan_feature, plan: hotel.plan, feature: audit_feature, enabled: true)
      guest = create(:guest, name: "Aina Rahman")
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      room = create(:booking_room, booking: booking, room_type: room_type, room_number: "208")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      create(:booking_folio, booking: booking, hotel: hotel, booking_room: room, name: "Room Guest Folio")

      described_class = self.class
      standard_tabs = %w[booking_details security_deposits billing_preferences room_and_rate source_details housekeeping_requests audit_trails]
      %w[booking_details folio_operations security_deposits billing_preferences guest_details room_and_rate source_details housekeeping_requests audit_trails].each do |tab|
        get hotel_booking_workspace_path(hotel, booking, tab: tab)

        expect(response).to have_http_status(:success), "expected #{tab} to render for #{described_class.description}"
        document = Nokogiri::HTML(response.body)
        expected_mode = standard_tabs.include?(tab) ? "standard" : "entity"
        expect(document.at_css("[data-layout-mode='#{expected_mode}']")).to be_present
        expect(document.css("h1").size).to eq(1)
        if expected_mode == "standard"
          expect(document.at_css('[data-testid="workspace-entity-rail"]')).to be_nil
          expect(document.at_xpath('//button[normalize-space()="Change Context"]')).to be_nil
          expect(document.css("main h2").size).to eq(1)
        else
          expect(document.at_css('[data-testid="workspace-entity-rail"]')).to be_present
        end

        active_navigation = document.at_css('#booking-workspace-tabs a[aria-current="page"]')
        if tab == "source_details"
          expect(active_navigation).to be_nil
        else
          expect(active_navigation).to be_present
        end
      end

      get hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests")
      expect(response.body).to include("Requests")
      expect(response.body).to include("Room requests and complaints for this booking")
    end

    it "renders every tab with its declared layout for a group child booking" do
      hotel.update!(plan: create(:plan))
      create(:plan_feature, plan: hotel.plan, feature: audit_feature, enabled: true)
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      room = create(:booking_room, booking: booking, room_type: room_type, room_number: "208")
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Aina Rahman"), is_primary: true)
      create(:booking_folio, booking: booking, hotel: hotel, booking_room: room, name: "Room Guest Folio")
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "209")
      create(:booking_guest, booking: sibling, guest: create(:guest, name: "Faiz Osman"), is_primary: true)
      create(:booking_folio, booking: sibling, hotel: hotel, name: "Sibling Guest Folio")

      standard_tabs = %w[booking_details security_deposits billing_preferences room_and_rate source_details housekeeping_requests audit_trails]
      %w[booking_details folio_operations security_deposits billing_preferences guest_details room_and_rate source_details housekeeping_requests audit_trails].each do |tab|
        get hotel_booking_workspace_path(hotel, booking, tab: tab)

        expect(response).to have_http_status(:success), "expected #{tab} to render for a group child booking"
        document = Nokogiri::HTML(response.body)
        expected_mode = standard_tabs.include?(tab) ? "standard" : "entity"
        expect(document.at_css("[data-layout-mode='#{expected_mode}']")).to be_present
        expect(document.css("h1").size).to eq(1)

        if expected_mode == "standard"
          expect(document.at_css('[data-testid="workspace-entity-rail"]')).to be_nil
          expect(document.at_xpath('//button[normalize-space()="Change Context"]')).to be_nil
        else
          expect(document.at_css('[data-testid="workspace-entity-rail"]')).to be_present
        end
      end
    end

    it "hides and blocks the audit tab when the feature is disabled" do
      get hotel_booking_workspace_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("Audit Trail")

      get hotel_booking_workspace_path(hotel, booking, tab: "audit_trails")

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("This feature isn't included in your plan. Upgrade to access it.")
    end

    it "shows the audit tab when the feature is enabled" do
      hotel.update!(plan: create(:plan))
      create(:plan_feature, plan: hotel.plan, feature: audit_feature, enabled: true)

      get hotel_booking_workspace_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Audit Trail")
    end

    it "renders the complete lifecycle action set with workspace return context" do
      role.permissions << manage_bookings
      expected_actions = {
        "confirmed" => [ "Check-in", "Cancel" ],
        "review_no_show" => [ "Backdated Check-in", "Mark No-show", "Cancel" ],
        "no_show" => [ "Reinstate" ],
        "checked_in" => [ "Check-out", "Edit Check-In", "Undo Check-in" ],
        "review_due_out" => [ "Review Late Checkout" ],
        "checkout_required" => [ "Complete Checkout" ]
      }

      expected_actions.each do |status, labels|
        booking.update_columns(status: status)
        path = hotel_booking_workspace_path(hotel, booking, tab: "booking_details")
        get path

        expect(response).to have_http_status(:success)
        document = Nokogiri::HTML(response.body)
        summary = document.at_css('[data-testid="booking-workspace-header"]')
        expect(summary.at_xpath('.//button[normalize-space()="Actions"]')).to be_present
        labels.each do |label|
          link = summary.at_xpath(".//a[normalize-space()='#{label}']")
          expect(link).to be_present, "expected #{label} for #{status}"
          expect(link.at_css("svg")).to be_present, "expected #{label} to include an icon"
          query = URI.decode_www_form(URI.parse(link["href"]).query.to_s).to_h
          expect(query["return_to"]).to eq(path)
        end
      end

      booking.update_columns(status: "completed")
      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details")
      summary = Nokogiri::HTML(response.body).at_css('[data-testid="booking-workspace-header"]')
      expect(summary.at_xpath('.//button[normalize-space()="Actions"]')).to be_nil
    end

    it "renders only the workspace frame for workspace turbo requests" do
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")

      get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate"), headers: { "Turbo-Frame" => "booking_workspace" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="booking_workspace"))
      expect(response.body).to include("Room &amp; Rate")
      expect(response.body).not_to include("<!DOCTYPE html>")
    end

    it "redirects legacy tab names to their Phase 6 names" do
      get hotel_booking_workspace_path(hotel, booking, tab: "room_charges")
      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate"))

      get hotel_booking_workspace_path(hotel, booking, tab: "billing_details")
      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences"))
    end

    it "renders rate warnings as alert dialogs without widening the workspace" do
      create(:booking_room, booking: booking)
      folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
      transaction_code = create(:transaction_code, hotel: hotel)
      rule = create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: transaction_code, target_folio: folio)

      get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate", alert_action: "change_rate")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="standard"')
      expect(response.body).to include('role="alertdialog"')
      expect(response.body).to include("Change stay or rate?")
      expect(response.body).not_to include('data-testid="workspace-action-drawer"')

      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences", alert_action: "routing_preview", folio_routing_rule_id: rule.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="standard"')
      expect(response.body).not_to include("Apply routing change?", "existing_and_future")
    end

    it "opens room changes in the booking action Sheet and renders guest editing inline" do
      role.permissions << manage_bookings
      guest = create(:booking_guest, booking: booking, is_primary: true)
      create(:booking_room, booking: booking)

      get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
      document = Nokogiri::HTML(response.body)
      change_room = document.at_xpath("//a[normalize-space()='Change Room']")
      expect(change_room["data-turbo-frame"]).to eq("booking_action_sheet")
      change_room_uri = URI.parse(change_room["href"])
      expect(change_room_uri.path).to eq(hotel_booking_action_edit_room_path(hotel, booking))
      expect(Rack::Utils.parse_nested_query(change_room_uri.query)).to eq(
        "return_to" => hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
      )

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: guest.id)
      document = Nokogiri::HTML(response.body)
      add_guest = document.at_xpath("//a[starts-with(normalize-space(), '+ Add guest')]")
      expect(add_guest["data-turbo-frame"]).to eq("booking_action_sheet")
      expect(add_guest["href"]).to include(hotel_booking_action_manage_guest_path(hotel, booking))
      form = document.at_css("form#guest-details-form[data-controller*='guest-details-editor']")
      footer = document.at_css('[data-testid="guest-details-footer"]')
      save_guest = footer.at_xpath(".//button[@type='submit' and normalize-space()='Save Guest']")
      view_grc = footer.at_xpath(".//a[normalize-space()='View GRC']")
      print_grc = footer.at_xpath(".//button[normalize-space()='Guest Registration Card']")
      print_status = footer.at_css("[data-document-print-status]")
      discard_alert = document.at_css('dialog[data-controller="confirm-discard"]')

      expect(form).to be_present
      expect(form["action"]).to eq(hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: guest.id))
      expect(form["method"]).to eq("post")
      expect(form.at_css('input[name="_method"][value="patch"]')).to be_present
      expect(form.css("fieldset.panel-field-set").size).to be >= 2
      expect(footer.parent["id"]).to eq("booking_workspace")
      expect(footer.ancestors("#booking-workspace-content")).to be_empty
      expect(footer["class"]).to include("border-t", "bg-card")
      expect(footer["class"]).not_to include("shadow")
      expect(document.at_xpath("//a[normalize-space()='Edit Guest']")).to be_nil
      expect(save_guest["form"]).to eq("guest-details-form")
      expect(view_grc["href"]).to eq(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(print_grc).to be_present
      expect(print_status.parent["class"]).to include("items-center")
      expect(print_status["class"]).not_to include("mt-2")
      print_menu = print_grc.ancestors('[data-controller="document-print"]').first
      expect(print_menu["data-document-print-url-value"]).to eq(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(discard_alert["role"]).to eq("alertdialog")
      expect(response.body).to include("Guest details", "Guest details recorded for this stay.", "GRC Actions", "Print")
      expect(response.body).not_to include("Stay Record", "Guest Profile")
      expect(response.body).to include("Enter full name", "guest@example.com", "+60 12-345 6789", "Search for a country", "Select a gender", "Select a document type", "Enter IC or passport number", "Select date of birth")
      expect(footer.at_xpath(".//button[@name='save_scope' and @value='snapshot']")).to be_present
      expect(footer.at_xpath(".//button[@name='save_scope' and @value='snapshot_and_profile']")).to be_present
      expect(response.body).not_to include("C Form")
    end

    it "keeps guest details in a two-column workspace even when drawer state is requested" do
      create(:booking_guest, booking: booking, is_primary: true)

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details", drawer: "deposit")

      expect(response.body).to include('data-layout-mode="entity"')
      expect(response.body).not_to include('data-testid="workspace-action-drawer"')
    end

    it "renders only true editor drawers" do
      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", drawer: "deposit")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="workspace-action-drawer"')
    end

    it "does not render removed billing drawer state" do
      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences", drawer: "billing")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Billing")
      expect(response.body).not_to include('data-testid="workspace-action-drawer"')
    end

    it "renders grouped standard destinations full width with a group Overview link" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "SIBLING-ROOM", reservation_number: 43)
      create(:booking_room, booking: booking, room_number: "103")
      create(:booking_room, booking: sibling, room_number: "104")

      get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(response.body).to include('data-layout-mode="standard"')
      expect(document.at_css("main h2").text).to eq("Room & Rate")
      expect(document.at_css('[data-testid="workspace-entity-rail"]')).to be_nil
      expect(document.at_css('[data-testid="booking-workspace-header"]').text).to include(group.formatted_reservation_number)
    end

    it "renders group-aware lifecycle controls as an actions dropdown in group context" do
      role.permissions << manage_bookings
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "completed")
      checkout_child = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      checkout_child.update_column(:status, "checked_in")
      create(:booking, hotel: hotel, group_booking: group, group_position: 3, status: "completed")
      create(:booking_room, booking: booking, room_number: "103")

      get hotel_booking_workspace_path(hotel, booking)

      expect(response).to have_http_status(:success)
      summary = Nokogiri::HTML(response.body).at_css('[data-testid="booking-workspace-header"]')
      expect(summary.at_xpath('.//button[normalize-space()="Actions"]')).to be_present
      expect(summary.css('a').map { |link| link.text.squish }).to include("Check-out")
      expect(summary.text).not_to include("Check-out...")
      expect(summary.text).to include("Partially in house")
      checkout_action = summary.at_xpath('.//a[normalize-space()="Check-out"]')
      expect(checkout_action.at_css("svg")).to be_present
      expect(checkout_action["href"]).to include(hotel_booking_action_checkout_path(hotel, checkout_child))
      expect(checkout_action["data-turbo-frame"]).to eq("booking_action_sheet")
    end

    it "renders group-aware actions on the group overview summary" do
      role.permissions << manage_bookings
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")

      get hotel_booking_workspace_path(hotel, booking, scope: "group")

      expect(response).to have_http_status(:success)
      summary = Nokogiri::HTML(response.body).at_css('[data-testid="booking-workspace-header"]')
      expect(summary.at_xpath('.//button[normalize-space()="Actions"]')).to be_present
      expect(summary.css('a').map { |link| link.text.squish }).to include("Check-out")
      expect(summary.text).to include(group.name)
    end

    it "renders deposits and requests as full-width standard destinations" do
      create(:deposit, booking: booking, hotel: hotel, amount: 150, status: "held")
      create(:housekeeping_request, booking: booking, request_details: "Fresh towels")
      create(:complaint_request, booking: booking, complaint_details: "Noisy hallway")

      get hotel_booking_workspace_path(hotel, booking, tab: "security_deposits")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="standard"')
      expect(response.body).to include("Deposits")
      expect(response.body).to include("MYR 150.00")

      get hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="standard"')
      expect(response.body).to include("Fresh towels")
      expect(response.body).to include("Noisy hallway")
    end

    it "omits child-booking rails from grouped deposits and requests" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "SIBLING-REQ", reservation_number: 44)
      sibling.update_column(:status, "completed")
      create(:booking_room, booking: booking, room_number: "103")
      create(:booking_room, booking: sibling, room_number: "104")

      get hotel_booking_workspace_path(hotel, booking, tab: "housekeeping_requests")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="standard"')
      request_document = Nokogiri::HTML(response.body)
      expect(request_document.at_css("main h2").text).to eq("Requests")
      expect(request_document.at_css('[data-testid="workspace-entity-rail"]')).to be_nil

      get hotel_booking_workspace_path(hotel, booking, tab: "security_deposits")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="standard"')
      expect(response.body).to include("Deposits")
      deposit_document = Nokogiri::HTML(response.body)
      expect(deposit_document.at_css('[data-testid="workspace-entity-rail"]')).to be_nil
      expect(deposit_document.at_css('[data-testid="booking-workspace-header"]').text).to include(group.formatted_reservation_number)
    end

    it "links group Overview bookings and preserves group identity on child pages" do
      group = create(:group_booking, hotel: hotel, name: "Hidden Group Name")
      booking.update!(group_booking: group, group_position: 1, guest_name: "Hanami Ume")
      room_type = create(:room_type, hotel: hotel, name: "Garden Prestige Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "105")

      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details", scope: "group")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      booking_link = document.at_css('section[aria-labelledby="group-overview-heading"] tbody a')
      expect(booking_link.text).to eq(booking.formatted_reservation_number)
      expect(booking_link["href"]).to include("tab=booking_details", "scope=booking")
      expect(document.at_css('[data-testid="workspace-entity-rail"]')).to be_nil

      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details", scope: "booking")
      child_document = Nokogiri::HTML(response.body)
      summary = child_document.at_css('[data-testid="booking-workspace-header"]')
      expect(summary.text).to include("Hidden Group Name", group.formatted_reservation_number)
      expect(summary.text).not_to include(booking.formatted_reservation_number)
      expect(child_document.at_css('section[aria-labelledby="booking-overview-heading"]')).to be_present
      expect(child_document.at_css('section[aria-labelledby="group-overview-heading"]')).to be_nil
      expect(child_document.at_css('[data-testid="workspace-entity-rail"]')).to be_nil
    end

    it "defaults a grouped booking Overview URL to the group comparison table" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2)

      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details")

      document = Nokogiri::HTML(response.body)
      expect(document.at_css('section[aria-labelledby="group-overview-heading"] table.panel-table')).to be_present
      expect(document.at_css('section[aria-labelledby="booking-overview-heading"]')).to be_nil
    end

    it "preserves explicit child scope across standard destination navigation" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate", scope: "booking")

      document = Nokogiri::HTML(response.body)
      overview_link = document.css("#booking-workspace-tabs a").find { |link| link.text.squish == "Overview" }
      expect(overview_link["href"]).to include("tab=booking_details", "scope=booking")
    end

    it "renders functional group overviews across every tab" do
      hotel.update!(plan: create(:plan))
      create(:plan_feature, plan: hotel.plan, feature: audit_feature, enabled: true)
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "GROUP-CHILD-2", reservation_number: 45)
      [ booking, sibling ].each_with_index do |child, index|
        room = create(:booking_room, booking: child, room_number: "20#{index + 1}")
        create(:booking_guest, booking: child, guest: create(:guest, name: "Group Guest #{index + 1}"), is_primary: true)
        create(:booking_folio, booking: child, hotel: hotel, booking_room: room, name: "Guest Folio #{index + 1}")
      end
      create(:deposit, booking: sibling, hotel: hotel, amount: 200, status: "held")
      create(:housekeeping_request, booking: sibling, request_details: "Group overview towels")

      expected_markers = {
        "booking_details" => "Conference Group",
        "security_deposits" => sibling.formatted_reservation_number,
        "billing_preferences" => "Register billing parties and settlement terms",
        "room_and_rate" => "Room &amp; Rate",
        "source_details" => "Group Source",
        "housekeeping_requests" => "Group overview towels",
        "audit_trails" => "Audit Trail"
      }

      expected_markers.each do |tab, marker|
        get hotel_booking_workspace_path(hotel, booking, tab: tab, scope: "group")

        expect(response).to have_http_status(:success), "expected group overview for #{tab}"
        expect(response.body).to include(marker)
        expect(response.body).to include(group.formatted_reservation_number)
        if tab == "booking_details"
          expect(response.body).to include(group.confirmation_token)
          expect(response.body).to include(group.formatted_receipt_number)
        end
        if tab == "room_and_rate"
          table = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="room-rate-heading"] table')
          expect(table.css("thead th").map { |header| header.text.strip }).to eq([ "Booking No.", "Stay Date", "Room Type", "Room", "Rate Plan", "Nightly Rate" ])
          expect(table.text).not_to include("Guest", "Status", "Estimated Room Value")
        end
      end
    end

    it "surfaces a stay-dates-vary notice instead of a combined group stay" do
      group = create(:group_booking, hotel: hotel, name: "Varied Group")
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2,
                       check_in: booking.check_in + 2.days, check_out: booking.check_out + 3.days)

      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details", scope: "group")

      overview = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="group-overview-heading"]')
      expect(overview.text).to include("Arrival and departure schedule")
      expect(overview.text).not_to include("Stay dates vary")
      expect(overview.text).to include("Arrivals occur on")
    end

    it "renders group references and a PanelsUI comparison table with separate arrival and departure columns" do
      group = create(
        :group_booking,
        hotel: hotel,
        source: "travel_agent",
        external_reference: "GROUP-EXTERNAL-42",
        channel_manager_reference: "GROUP-CHANNEL-42"
      )
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(
        :booking,
        hotel: hotel,
        group_booking: group,
        group_position: 1,
        check_in: booking.check_in - 2.days,
        check_out: booking.check_out - 1.day,
        reservation_number: 43
      )

      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details", scope: "group")

      overview = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="group-overview-heading"]')
      table = overview.at_css("table.panel-table")
      expect(overview.text).to include("Travel Agent", "GROUP-EXTERNAL-42", "GROUP-CHANNEL-42")
      expect(table).to be_present
      expect(table.at_css("caption").text).to eq("Stay")
      expect(table.css("thead th").map { |header| header.text.strip }).to eq(
        [ "Booking No.", "Primary guest", "Room", "Arrival", "Departure", "Nights", "Pax", "Status", "Balance" ]
      )
      expect(table.css("tbody tr").map { |row| row.at_css("td").text.strip }).to eq(
        [ first_child.formatted_reservation_number, booking.formatted_reservation_number ]
      )
      expect(table.text).to include(
        first_child.check_in.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"),
        first_child.check_out.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y")
      )
      expect(table.css("thead th").map { |header| header.text.strip }).not_to include("Rate Plan")
    end

    it "renders the same stay table with a single row for a standalone booking" do
      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details")

      overview = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="booking-overview-heading"]')
      table = overview.at_css("table.panel-table")
      expect(table).to be_present
      expect(table.css("thead th").map { |header| header.text.strip }).to eq(
        [ "Booking No.", "Primary guest", "Room", "Arrival", "Departure", "Nights", "Pax", "Status", "Balance" ]
      )
      expect(table.css("tbody tr").size).to eq(1)
      expect(table.at_css("tfoot")).to be_nil
      expect(table.at_css("tbody a")).to be_nil
    end

    it "leads the group references table with the group's own row" do
      group = create(:group_booking, hotel: hotel, source: "travel_agent")
      booking.update!(group_booking: group, group_position: 1)
      create(:booking, hotel: hotel, group_booking: group, group_position: 2, reservation_number: 77)

      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details", scope: "group")

      overview = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="group-overview-heading"]')
      table = overview.css("table.panel-table").last
      expect(table.css("thead th").map { |header| header.text.strip }).to eq(
        [ "Booking No.", "Confirmation code", "Receipt No.", "Source", "Invoice No.", "Folio Account", "Guest Registration" ]
      )

      body_rows = table.css("tbody tr")
      expect(body_rows.size).to eq(3)
      expect(body_rows.first.text).to include(group.formatted_reservation_number, group.confirmation_token, "Group")
      expect(body_rows.drop(1).map(&:text)).to all(satisfy { |text| !text.include?("Group") })
    end

    it "renders an Edit Dates launch link on the group overview booking details tab" do
      role.permissions << manage_bookings
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details", scope: "group")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      link = document.at_xpath("//a[normalize-space()='Edit Dates']")
      expect(link).to be_present
      link_uri = URI.parse(link["href"])
      expect(link_uri.path).to eq(hotel_booking_action_edit_dates_path(hotel, booking))
      return_to = Rack::Utils.parse_nested_query(link_uri.query).fetch("return_to")
      return_uri = URI.parse(return_to)
      expect(return_uri.path).to eq(hotel_booking_workspace_path(hotel, booking))
      expect(Rack::Utils.parse_nested_query(return_uri.query)).to eq("tab" => "booking_details", "scope" => "group")
    end

    it "hides the Edit Dates launch link on the group overview without manage_bookings permission" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      get hotel_booking_workspace_path(hotel, booking, tab: "booking_details", scope: "group")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_xpath("//a[normalize-space()='Edit Dates']")).to be_nil
    end

    it "renders legacy grouped folio scope with the first child's primary folio without redirecting" do
      group = create(:group_booking, hotel: hotel)
      later_child = booking
      later_child.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      fallback_folio = create(:booking_folio, :secondary, booking: first_child, hotel: hotel)
      primary_folio = create(:booking_folio, booking: first_child, hotel: hotel, is_primary: true)

      get hotel_booking_workspace_path(hotel, later_child, tab: "folio_operations", scope: "group")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('nav[aria-label="Booking folios"] a[aria-current="page"]')["href"]).to include(
        first_child.id.to_s,
        "folio_id=#{primary_folio.id}"
      )
      expect(document.at_css("#folio-operations-heading").text).to eq(primary_folio.display_name)
    end

    it "renders the first child's primary guest without redirecting" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      create(:booking_guest, booking: first_child, guest: create(:guest), is_primary: false)
      primary_guest = create(:booking_guest, booking: first_child, guest: create(:guest), is_primary: true)

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('[data-testid="workspace-entity-rail"] a[aria-current="page"]').text).to include(primary_guest.guest.name)
      expect(document.at_css("form#guest-details-form")["action"]).to include(first_child.id.to_s, "booking_guest_id=#{primary_guest.id}")
    end

    it "gates each group's Add Guest action on that child's own status" do
      role.permissions << manage_bookings
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      booking.update_column(:status, "confirmed")
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      first_child.update_column(:status, "pending")
      create(:booking_guest, booking: first_child, guest: create(:guest), is_primary: true)
      add_guest_in = lambda do |child|
        Nokogiri::HTML(response.body).at_xpath(
          "//section[@aria-labelledby='desktop-guest-group-#{child.id}']//a[starts-with(normalize-space(), '+ Add guest')]"
        )
      end

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

      expect(add_guest_in.call(first_child)).to be_nil
      expect(add_guest_in.call(booking)["href"]).to include(booking.id.to_s)

      first_child.update_column(:status, "confirmed")
      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details")

      expect(add_guest_in.call(first_child)["href"]).to include(first_child.id.to_s)
    end

    it "falls back to the first folio and guest when the first child has no primary entities" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      fallback_folio = create(:booking_folio, :secondary, booking: first_child, hotel: hotel, folio_sequence: 3)
      fallback_guest = create(:booking_guest, booking: first_child, guest: create(:guest), is_primary: false)

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")
      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).at_css("#folio-operations-heading").text).to eq(fallback_folio.display_name)

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details")
      expect(response).to have_http_status(:success)
      expect(Nokogiri::HTML(response.body).at_css('[data-testid="workspace-entity-rail"] a[aria-current="page"]').text).to include(fallback_guest.guest.name)
    end

    it "renders the normal empty state when the first child has no folios" do
      role.permissions << manage_folio_windows
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      create(:booking_folio, booking: booking, hotel: hotel)

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")
      expect(response).to have_http_status(:success)
      expect(response.body).to include("No folios are available.")
      add_action = Nokogiri::HTML(response.body).at_xpath("//main//a[normalize-space()='Add Folio']")
      expect(add_action["href"]).to eq(new_folio_window_hotel_booking_workspace_path(hotel, first_child))
    end

    it "targets the selected folio's concrete child in context and folio actions" do
      role.permissions << manage_folio_windows
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      create(:booking_room, booking: first_child, room_number: "105")
      folio = create(:booking_folio, booking: first_child, hotel: hotel, name: "First Child Folio")

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations")

      document = Nokogiri::HTML(response.body)
      context = document.at_css("#folio-operations-heading").previous_element.text
      edit_link = document.at_xpath("//a[normalize-space()='Edit']")
      expected_close_path = close_folio_window_hotel_booking_workspace_path(hotel, first_child, folio)
      close_form = document.css("form").find { |form| form["action"] == expected_close_path }
      add_link = document.at_xpath("//*[@data-testid='workspace-entity-rail']//a[starts-with(normalize-space(), '+ Add folio')]")
      expect(context).to include("Room 105", "Booking #{first_child.formatted_reservation_number}")
      expect(edit_link["href"]).to eq(edit_folio_window_hotel_booking_workspace_path(hotel, first_child, folio))
      expect(close_form["action"]).to eq(expected_close_path)
      expect(add_link["href"]).to eq(new_folio_window_hotel_booking_workspace_path(hotel, first_child))
    end

    it "ignores folio and guest IDs outside the current group" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      local_folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Local Folio")
      local_guest = create(:booking_guest, booking: booking, guest: create(:guest, name: "Local Guest"), is_primary: true)
      foreign_booking = create(:booking, hotel: other_hotel)
      foreign_folio = create(:booking_folio, booking: foreign_booking, hotel: other_hotel, name: "Foreign Folio Secret")
      foreign_guest = create(:booking_guest, booking: foreign_booking, guest: create(:guest, name: "Foreign Guest Secret"), is_primary: true)

      get hotel_booking_workspace_path(hotel, booking, tab: "folio_operations", folio_id: foreign_folio.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(local_folio.display_name)
      expect(response.body).not_to include("Foreign Folio Secret")

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: foreign_guest.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include(local_guest.guest.name)
      expect(response.body).not_to include("Foreign Guest Secret")
    end

    it "keeps explicit grouped entity selections canonical and removes synthetic overview links" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_folio, booking: booking, hotel: hotel)
      sibling_folio = create(:booking_folio, booking: sibling, hotel: hotel)

      get hotel_booking_workspace_path(hotel, sibling, tab: "folio_operations", folio_id: sibling_folio.id)

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      header = document.at_css('[data-testid="booking-workspace-header"]')
      expect(header.text).to include(group.name, group.formatted_reservation_number)
      expect(header.text).not_to include("Booking #{sibling.formatted_reservation_number}")
      rail = document.at_css('[data-testid="workspace-entity-rail"]')
      expect(rail.text).not_to include("Group Statement", "Group Guest Overview")
      expect(rail.css("h3").map { |heading| heading.text.squish }).to include(sibling.formatted_reservation_number)
      expect(document.at_css('nav[aria-label="Booking folios"] a[aria-current="page"]').text).to include(sibling_folio.display_name)
    end

    it "preserves group identity for an explicitly selected group guest" do
      group = create(:group_booking, hotel: hotel, name: "Guest Tour Group")
      booking.update!(group_booking: group, group_position: 1)
      guest = create(:booking_guest, booking: booking, guest: create(:guest, name: "Concrete Guest"), is_primary: true)

      get hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: guest.id)

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      header = document.at_css('[data-testid="booking-workspace-header"]')
      expect(header.text).to include("Guest Tour Group", group.formatted_reservation_number)
      expect(document.at_css('[data-testid="workspace-entity-rail"] a[aria-current="page"]').text).to include("Concrete Guest")
      expect(document.at_css("#booking-workspace-content #guest-details-panel")).to be_present
    end

    it "renders group deposits under group security deposits" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:group_deposit, group_booking: group, hotel: hotel, amount: 450, external_reference: "GROUP-DEP-450")

      get hotel_booking_workspace_path(hotel, booking, tab: "security_deposits", scope: "group")

      expect(response).to have_http_status(:success)
      panel = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="security-deposits-heading"]')
      expect(panel.text).to include("Group Deposits", "GROUP-DEP-450", "MYR 450.00")
    end

    it "keeps group billing preferences focused on billing parties" do
      group = create(:group_booking, hotel: hotel, name: "Overview Group")
      booking.update!(group_booking: group, group_position: 1)
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Child-only payer"), is_primary: true)

      get hotel_booking_workspace_path(hotel, booking, tab: "billing_preferences", scope: "group")

      expect(response).to have_http_status(:success)
      panel = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="billing-preferences-heading"]')
      expect(panel.text).to include("Register billing parties", "Billing parties", "+ Add billing party", "Child-only payer")
      expect(panel.text).not_to include("Arrangement name", "+ Add arrangement")
    end

    it "renders a directed empty state for a booking without a room" do
      get hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No room is attached to this booking")
    end

    it "requires view booking permission" do
      role.permissions.delete(view_bookings)

      get hotel_booking_workspace_path(hotel, booking)

      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH /hotel/:hotel_id/bookings/:booking_id/workspace" do
    before { role.permissions << manage_bookings }

    it "updates the selected stay snapshot without changing the reusable guest" do
      guest = create(:guest, name: "Reusable Guest")
      booking_guest = create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      patch hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id), params: {
        guest: { name: "Stay Snapshot", email: "stay@example.com", country: "Malaysia", document_type: "passport" },
        save_scope: "snapshot"
      }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id))
      expect(booking_guest.reload).to have_attributes(name_snapshot: "Stay Snapshot", email_snapshot: "stay@example.com")
      expect(guest.reload.name).to eq("Reusable Guest")
    end

    it "updates the reusable guest only through the explicit split-save scope" do
      guest = create(:guest, name: "Reusable Guest")
      booking_guest = create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      patch hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id), params: {
        guest: { name: "Shared Guest", email: "shared@example.com", country: "Malaysia", document_type: "passport" },
        save_scope: "snapshot_and_profile"
      }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id))
      expect(booking_guest.reload.name_snapshot).to eq("Shared Guest")
      expect(guest.reload.name).to eq("Shared Guest")
    end

    it "renders submitted values and field errors without partially updating" do
      guest = create(:guest, name: "Original Guest", email: "original@example.com")
      booking_guest = create(:booking_guest, booking: booking, guest: guest, is_primary: true, name_snapshot: "Original Guest")

      patch hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id), params: {
        guest: { name: "", email: "submitted@example.com", country: "Malaysia", document_type: "passport" },
        save_scope: "snapshot_and_profile"
      }

      expect(response).to have_http_status(:unprocessable_content)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("[data-guest-details-error-summary]").text).to include("Name can't be blank")
      expect(document.at_css("input[name='guest[email]']")["value"]).to eq("submitted@example.com")
      expect(document.at_css("input[name='guest[name]']")["aria-invalid"]).to eq("true")
      expect(booking_guest.reload.name_snapshot).to eq("Original Guest")
      expect(guest.reload).to have_attributes(name: "Original Guest", email: "original@example.com")
    end

    it "preserves boat-transfer values and field errors" do
      hotel.update!(allow_boat_information: true)
      booking_guest = create(:booking_guest, booking: booking, guest: create(:guest, name: "Boat Guest"), is_primary: true)

      patch hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id), params: {
        guest: { name: "Boat Guest", country: "Malaysia", document_type: "passport" },
        booking_guest: { boat_transfer_range: "2026-08-02T10:00/2026-08-01T10:00" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      document = Nokogiri::HTML(response.body)
      invalid_boat_field = document.css('[data-invalid="true"]').find { |field| field.text.include?("Boat-in and boat-out") }
      expect(document.at_css("[data-guest-details-error-summary]").text).to include("Boat out at must be after boat in time")
      expect(invalid_boat_field).to be_present
      expect(invalid_boat_field.text).to include("must be after boat in time")
      expect(document.at_css("input[name='booking_guest[boat_transfer_range]']")["value"])
        .to eq("2026-08-02T10:00/2026-08-01T10:00")
      expect(booking_guest.reload).to have_attributes(boat_in_at: nil, boat_out_at: nil)
    end

    it "saves both boat times from one range field" do
      hotel.update!(allow_boat_information: true)
      booking_guest = create(:booking_guest, booking: booking, guest: create(:guest, name: "Boat Guest"), is_primary: true)

      patch hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id), params: {
        guest: { name: "Boat Guest", country: "Malaysia", document_type: "passport" },
        booking_guest: { boat_transfer_range: "2026-08-01T09:30/2026-08-04T16:45" }
      }

      expect(booking_guest.reload.boat_in_at.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M")).to eq("2026-08-01T09:30")
      expect(booking_guest.boat_out_at.in_time_zone(hotel.hotel_time_zone).strftime("%Y-%m-%dT%H:%M")).to eq("2026-08-04T16:45")
    end

    it "leaves stored boat times alone when the range field is not submitted" do
      hotel.update!(allow_boat_information: true)
      booking_guest = create(:booking_guest, booking: booking, guest: create(:guest, name: "Boat Guest"), is_primary: true)
      booking_guest.update!(boat_in_at: "2026-08-01T09:30", boat_out_at: "2026-08-04T16:45")

      patch hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id), params: {
        guest: { name: "Boat Guest", country: "Malaysia", document_type: "passport" }
      }

      expect(booking_guest.reload.boat_in_at).to be_present
      expect(booking_guest.boat_out_at).to be_present
    end

    it "ignores forged boat-transfer fields when the hotel disables them" do
      hotel.update!(allow_boat_information: false)
      booking_guest = create(:booking_guest, booking: booking, guest: create(:guest, name: "No Boat Guest"), is_primary: true)

      patch hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id), params: {
        guest: { name: "No Boat Guest", country: "Malaysia", document_type: "passport" },
        booking_guest: { boat_transfer_range: "2026-08-01T10:00/2026-08-02T10:00" }
      }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id))
      expect(booking_guest.reload).to have_attributes(boat_in_at: nil, boat_out_at: nil)
    end

    it "rejects a booking guest outside the workspace booking or group" do
      local_guest = create(:booking_guest, booking: booking, guest: create(:guest, name: "Local Guest"), is_primary: true)
      foreign_booking = create(:booking, hotel: other_hotel)
      foreign_guest = create(:booking_guest, booking: foreign_booking, guest: create(:guest, name: "Foreign Guest"), is_primary: true)

      patch hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: foreign_guest.id), params: {
        guest: { name: "Forged Update", country: "Malaysia" }
      }

      expect(response).to have_http_status(:not_found)
      expect(local_guest.reload.name_snapshot).not_to eq("Forged Update")
      expect(foreign_guest.reload.name_snapshot).not_to eq("Forged Update")
    end

    it "rejects a sibling guest submitted through another child booking URL" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      sibling_guest = create(:booking_guest, booking: sibling, guest: create(:guest, name: "Sibling Guest"), is_primary: true)

      patch hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: sibling_guest.id), params: {
        guest: { name: "Forged Sibling Update", country: "Malaysia" }
      }

      expect(response).to have_http_status(:not_found)
      expect(sibling_guest.reload.name_snapshot).not_to eq("Forged Sibling Update")
    end
  end

  describe "GET /hotel/:hotel_id/bookings/:booking_id/workspace/audit_trail" do
    before do
      hotel.update!(plan: create(:plan))
      create(:plan_feature, plan: hotel.plan, feature: audit_feature, enabled: true)
    end

    it "renders the booking audit timeline in the right offcanvas sheet" do
      create(:booking_audit_log, hotel: hotel, auditable: booking, user: user,
        old_value: { "status" => "pending" }, new_value: { "status" => "confirmed" })

      get audit_trail_hotel_booking_workspace_path(hotel, booking),
        headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      frame = document.at_css('turbo-frame#offcanvas_drawer[data-offcanvas-variant="right"]')
      expect(frame).to be_present
      expect(frame["data-offcanvas-label"]).to eq("Audit Trail")
      expect(frame.text).to include("Audit Trail", "View Changes", "Pending", "Confirmed")
      expect(frame.at_css('[data-action="click->offcanvas#close"]')).to be_present
    end

    it "renders the existing empty audit state" do
      get audit_trail_hotel_booking_workspace_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No audit history recorded.", "Important booking activity will appear here.")
    end

    it "blocks access when the feature is disabled" do
      hotel.plan.plan_features.find_by!(feature: audit_feature).update!(enabled: false)

      get audit_trail_hotel_booking_workspace_path(hotel, booking)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("This feature isn't included in your plan. Upgrade to access it.")
    end

    it "blocks access without view_bookings permission" do
      role.permissions.delete(view_bookings)

      get audit_trail_hotel_booking_workspace_path(hotel, booking)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end

    it "does not expose another hotel's booking" do
      other_booking = create(:booking, hotel: other_hotel)

      get audit_trail_hotel_booking_workspace_path(hotel, other_booking)

      expect(response).to have_http_status(:not_found)
    end
  end
end
