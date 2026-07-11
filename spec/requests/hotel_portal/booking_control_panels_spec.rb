# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::BookingControlPanels", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_bookings) { Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View Bookings" } }
  let(:manage_bookings) { Permission.find_or_create_by!(slug: "manage_bookings") { |permission| permission.name = "Manage Bookings" } }
  let(:manage_folio_windows) { Permission.find_or_create_by!(slug: "manage_folio_windows") { |permission| permission.name = "Manage Folio Windows" } }
  let(:manage_folio_movements) { Permission.find_or_create_by!(slug: "manage_folio_movements") { |permission| permission.name = "Manage Folio Movements" } }
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

  describe "GET /hotel/:hotel_id/booking-control-panels/:booking_id" do
    it "renders plain booking, guest, stay, source, and room details" do
      guest = create(:guest, name: "Aina Rahman")
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")

      get hotel_booking_control_panel_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Booking control panel")
      expect(response.body).to include(booking.confirmation_token)
      expect(response.body).to include(booking.formatted_reservation_number)
      expect(response.body).to include(booking.formatted_receipt_number)
      expect(response.body).to include("Aina Rahman")
      expect(response.body).to include("Garden Suite")
      expect(response.body).to include("208")
      expect(response.body).to include(booking.check_in.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"))
      expect(response.body).to include(booking.check_out.in_time_zone(hotel.hotel_time_zone).strftime("%d %b %Y"))
      expect(response.body).to include("overflow-hidden rounded-xl border border-slate-200")
    end

    it "renders explicit rate, source, and deposit form states" do
      create(:booking_room, booking: booking, nightly_rate_snapshot: {})

      get hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")
      room_rate_table = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="room-rate-heading"] table')
      expect(room_rate_table.text).to include("Stay Date", "Room Type", "Room", "Rate Plan", "Nightly Rate", "Rate unavailable")
      expect(room_rate_table.text).not_to include("MYR 0.00", "Posted to folio", "Check-in", "Occupancy", "Status")
      expect(response.body).not_to include("Nightly Rate Schedule")

      get hotel_booking_control_panel_path(hotel, booking, tab: "source_details")
      expect(response.body).to include("Not provided")

      get hotel_booking_control_panel_path(hotel, booking, tab: "security_deposits")
      expect(response.body).to include("border border-slate-300 bg-white")
      expect(response.body).to include("No held deposit is available to release")

      get hotel_booking_control_panel_path(hotel, booking, tab: "housekeeping_requests")
      expect(response.body).to include('class="flex h-full min-h-0 flex-col"')
      expect(response.body).to include("grid min-h-0 flex-1")
    end

    it "renders one active standalone booking row without Overview" do
      room_type = create(:room_type, hotel: hotel, name: "Executive Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")

      get hotel_booking_control_panel_path(hotel, booking, tab: "booking_details")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      nav = document.at_css('nav[aria-label="Booking context menu"]')
      links = nav.css("a")
      expect(document.at_css("aside h2").text).to include("Booking / Details")
      expect(links.size).to eq(1)
      expect(links.first.text.squish).to eq("Room 208 Executive Suite - Fallback Name")
      expect(links.first["class"]).to include("bg-slate-900")
      expect(links.first.at_css("svg")).to be_present
      expect(nav.text).not_to include("Overview", booking.formatted_reservation_number, booking.status.humanize)
    end

    it "keeps Change Billing Routes above the standalone billing row" do
      role.permissions << manage_folio_movements
      create(:booking_room, booking: booking, room_number: "208")

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      aside = document.at_css('aside[aria-label="Booking context"]')
      billing_action = aside.at_xpath(".//a[normalize-space()='Change Billing Routes']")
      booking_row = aside.at_css('nav[aria-label="Booking context menu"] a')
      expect(document.at_css("aside h2").text).to include("Booking / Billing")
      expect(billing_action).to be_present
      expect(booking_row).to be_present
      expect(billing_action.path).not_to eq(booking_row.path)
      expect(aside.inner_html.index("Change Billing Routes")).to be < aside.inner_html.index("Booking context menu")
    end

    it "shows recorded rates even when booking dates are invalid" do
      booking.update!(check_in: Time.zone.local(2026, 6, 30, 15), check_out: Time.zone.local(2026, 6, 30, 12))
      room_type = create(:room_type, hotel: hotel, name: "Garden Prestige Suite")
      rate_plan = create(:rate_plan, room_type: room_type, name: "Standard Rate")
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan, room_number: "107", nightly_rate_snapshot: { "2026-06-30" => { "price" => "740.0" } })

      get hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")

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

      get hotel_booking_control_panel_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Folio Operations")
      expect(response.body).to include("Billing Preferences")
      expect(response.body).not_to include("PRIVATE FOLIO MARKER")

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("PRIVATE FOLIO MARKER")
      expect(response.body).to include("PRIVATE TRANSACTION MARKER")
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('nav[aria-label="Folio operation sections"]')).to be_nil
      expect(response.body).not_to include("Activity Log")
      expect(document.at_css('[data-folio-ledger-section-param="forecasted"]')["aria-expanded"]).to eq("false")
      expect(document.css("tr[data-section='posted']").all? { |row| !row["class"].to_s.split.include?("hidden") }).to be(true)
      expect(document.css("tr[data-section='forecasted']").all? { |row| row["class"].to_s.split.include?("hidden") }).to be(true)

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", folio_id: folio.id, folio_tab: "activity")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("PRIVATE TRANSACTION MARKER")
      expect(response.body).not_to include("Activity Log")

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", folio_id: target_folio.id)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("PRIVATE ROUTE MARKER", "Advanced Billing Rules", "Billing Instructions")
    end

    it "renders standalone billing preferences from billing parties" do
      guest = create(:guest, name: "Aina Rahman")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      corporate_account = create(:account, :corporate, name: "Acme Engineering")
      hotel_corporate_account = create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_account, direct_bill_enabled: true)
      company_party = create(:booking_billing_party, :company, booking: booking, hotel: hotel, hotel_corporate_account: hotel_corporate_account)
      create(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: company_party, hotel_corporate_account: hotel_corporate_account, name: "Corporate Folio")

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences")

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
      account = create(:hotel_corporate_account, hotel: hotel, direct_bill_enabled: true)
      company_party = create(:booking_billing_party, :company, booking: booking, hotel: hotel, hotel_corporate_account: account)
      create(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: company_party,
        hotel_corporate_account: account, name: "Child Corporate Folio")

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences")

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

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", billing_editor: "new_party")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Add billing party", "Inline Company", "Settlement type")
      document = Nokogiri::HTML(response.body)
      form = document.at_css("form[action*='add_billing_party']")
      expect(form).to be_present
      expect(form["data-turbo-frame"]).not_to eq("offcanvas_drawer")
    end

    it "uses the same collapsible booking hierarchy for folios and guests" do
      guest = create(:guest, name: "Rail Guest Name")
      booking_guest = create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)

      folio_document = Nokogiri::HTML(response.body)
      folio_nav = folio_document.at_css('nav[aria-label="Booking folios"]')
      folio_summary = folio_nav.at_css("details[open] summary")
      expect(folio_summary.text.squish).to include("Room 208", "Garden Suite - Rail Guest Name")
      expect(folio_summary.text).not_to include(booking.formatted_reservation_number)
      expect(folio_summary.at_css('.group-open\\:rotate-90')).to be_present
      expect(folio_nav.at_css("a.bg-slate-900").text).to include(folio.display_name)
      expect(folio_nav.to_html).not_to include("border-l-2")

      get hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id)

      guest_document = Nokogiri::HTML(response.body)
      guest_nav = guest_document.at_css('nav[aria-label="Booking guests"]')
      guest_summary = guest_nav.at_css("details[open] summary")
      expect(guest_summary.text.squish).to include("Room 208", "Garden Suite - Rail Guest Name")
      expect(guest_summary.text).not_to include(booking.formatted_reservation_number)
      expect(guest_nav.at_css("a.bg-slate-900").text).to include(guest.name)
      expect(guest_nav.to_html).not_to include("border-l-2")
    end

    it "renders Add Folio in the folio left rail using the control-panel flow" do
      role.permissions << manage_folio_windows
      create(:booking_guest, booking: booking, is_primary: true)
      create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations")

      document = Nokogiri::HTML(response.body)
      add_folio = document.at_xpath("//a[normalize-space()='+ Add Folio']")
      expect(add_folio).to be_present
      expect(add_folio["href"]).to eq(new_folio_window_hotel_booking_control_panel_path(hotel, booking))
      expect(add_folio["href"]).not_to eq(new_window_hotel_folio_path(hotel, booking))
      expect(add_folio["data-turbo-frame"]).to eq("offcanvas_drawer")
    end

    it "keeps folio tree links free of obsolete subtab state" do
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", folio_tab: "forecast")

      document = Nokogiri::HTML(response.body)
      folio_link = document.at_css("nav[aria-label='Booking folios'] a[href*='folio_id=#{folio.id}']")
      expect(folio_link).to be_present
      expect(folio_link["href"]).not_to include("folio_tab")
    end

    it "opens only the current booking in grouped entity rails" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "COLLAPSED-SIBLING")
      sibling.update_column(:status, "checkout_required")
      create(:booking_room, booking: booking, room_number: "101")
      create(:booking_room, booking: sibling, room_number: "102")
      create(:booking_folio, booking: booking, hotel: hotel, name: "Current Folio")
      create(:booking_folio, booking: sibling, hotel: hotel, name: "Sibling Folio")

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations")
      follow_redirect!

      document = Nokogiri::HTML(response.body)
      details = document.at_css('nav[aria-label="Bookings and folios"]').css("details")
      expect(details.size).to eq(2)
      expect(details.first.key?("open")).to be(true)
      expect(details.last.key?("open")).to be(false)
      expect(details.first.at_css("summary").text.squish).to include("In house Room 101", booking.guest_name)
      expect(details.last.at_css("summary").text.squish).to include("Checkout due Room 102", sibling.guest_name)
      current_folio_link = details.first.at_css('a[href*="folio_id="]')
      expect(current_folio_link["data-turbo-frame"]).to eq("_top")
    end

    it "marks grouped folio collapsibles for in-page state preservation" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_room, booking: booking, room_number: "101")
      create(:booking_room, booking: sibling, room_number: "102")
      create(:booking_folio, booking: booking, hotel: hotel)
      create(:booking_folio, booking: sibling, hotel: hotel)

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations")
      follow_redirect!

      document = Nokogiri::HTML(response.body)
      nav = document.at_css('nav[data-controller="booking-entity-tree"]')
      expect(nav["data-booking-entity-tree-scope-value"]).to eq("Bookings and folios")
      expect(nav.css('details[data-action="toggle->booking-entity-tree#remember"]').size).to eq(2)
    end

    it "does not allow access to another hotel's booking" do
      other_booking = create(:booking, hotel: other_hotel)

      get hotel_booking_control_panel_path(hotel, other_booking)

      expect(response).to have_http_status(:not_found)
    end

    it "renders every control panel tab with its declared layout" do
      guest = create(:guest, name: "Aina Rahman")
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      room = create(:booking_room, booking: booking, room_type: room_type, room_number: "208")
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)
      create(:booking_folio, booking: booking, hotel: hotel, booking_room: room, name: "Room Guest Folio")

      described_class = self.class
      %w[booking_details folio_operations security_deposits billing_preferences guest_details room_and_rate source_details housekeeping_requests audit_trails].each do |tab|
        get hotel_booking_control_panel_path(hotel, booking, tab: tab)

        expect(response).to have_http_status(:success), "expected #{tab} to render for #{described_class.description}"
        expect(response.body).to include("data-layout-mode=")
      end

      get hotel_booking_control_panel_path(hotel, booking, tab: "housekeeping_requests")
      expect(response.body).to include("Requests")
      expect(response.body).to include("Room requests and complaints for this booking")
    end

    it "renders the complete lifecycle action set with control-panel return context" do
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
        path = hotel_booking_control_panel_path(hotel, booking, tab: "booking_details")
        get path

        expect(response).to have_http_status(:success)
        document = Nokogiri::HTML(response.body)
        summary = document.at_css('section[aria-label="Booking summary"]')
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
      get hotel_booking_control_panel_path(hotel, booking, tab: "booking_details")
      summary = Nokogiri::HTML(response.body).at_css('section[aria-label="Booking summary"]')
      expect(summary.at_xpath('.//button[normalize-space()="Actions"]')).to be_nil
    end

    it "renders only the workspace frame for workspace turbo requests" do
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208")

      get hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate"), headers: { "Turbo-Frame" => "booking_control_panel_workspace" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(%(id="booking_control_panel_workspace"))
      expect(response.body).to include("Room &amp; Rate")
      expect(response.body).not_to include("<!DOCTYPE html>")
    end

    it "redirects legacy tab names to their Phase 6 names" do
      get hotel_booking_control_panel_path(hotel, booking, tab: "room_charges")
      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate"))

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_details")
      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences"))
    end

    it "renders rate warnings as alert dialogs without widening the workspace" do
      create(:booking_room, booking: booking)
      folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
      transaction_code = create(:transaction_code, hotel: hotel)
      rule = create(:folio_routing_rule, hotel: hotel, booking: booking, transaction_code: transaction_code, target_folio: folio)

      get hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate", alert_action: "change_rate")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).to include('role="alertdialog"')
      expect(response.body).to include("Change stay or rate?")
      expect(response.body).not_to include('data-testid="control-panel-action-drawer"')

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", alert_action: "routing_preview", folio_routing_rule_id: rule.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).not_to include("Apply routing change?", "existing_and_future")
    end

    it "opens room changes offcanvas and renders guest editing inline" do
      role.permissions << manage_bookings
      guest = create(:booking_guest, booking: booking, is_primary: true)
      create(:booking_room, booking: booking)

      get hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")
      document = Nokogiri::HTML(response.body)
      change_room = document.at_xpath("//a[normalize-space()='Change Room']")
      expect(change_room["data-turbo-frame"]).to eq("offcanvas_drawer")
      expect(change_room["href"]).to eq(hotel_booking_transaction_edit_booking_timeline_path(hotel, booking))

      get hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", booking_guest_id: guest.id)
      document = Nokogiri::HTML(response.body)
      add_guest = document.at_xpath("//a[normalize-space()='+ Add Guest']")
      expect(add_guest["data-turbo-frame"]).to eq("offcanvas_drawer")
      form = document.at_css("form#guest-details-form[data-controller*='guest-details-editor']")
      footer = document.at_css('[data-testid="guest-details-footer"]')
      save_guest = footer.at_xpath(".//button[@type='submit' and normalize-space()='Save Guest']")
      view_grc = footer.at_xpath(".//a[normalize-space()='View GRC']")
      print_grc = footer.at_xpath(".//button[normalize-space()='Guest Registration Card']")
      print_status = footer.at_css("[data-document-print-status]")
      discard_alert = document.at_css('dialog[data-controller="confirm-discard"]')

      expect(form).to be_present
      expect(footer.parent["id"]).to eq("booking_control_panel_workspace")
      expect(footer.ancestors("#booking-control-panel-content")).to be_empty
      expect(footer["class"]).to include("border-t", "bg-white")
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
      expect(response.body).to include("Guest Details", "Guest details recorded for this stay.", "GRC Actions", "Print")
      expect(response.body).not_to include("Stay Record", "Guest Profile")
      expect(response.body).to include("Enter full name", "guest@example.com", "+60 12-345 6789", "Select country", "Select gender", "Select document type", "Enter IC or passport number", "Select date")
      expect(footer.at_xpath(".//button[@name='save_scope' and @value='snapshot']")).to be_present
      expect(footer.at_xpath(".//button[@name='save_scope' and @value='snapshot_and_profile']")).to be_present
      expect(response.body).not_to include("C Form")
    end

    it "keeps guest details in a two-column workspace even when drawer state is requested" do
      create(:booking_guest, booking: booking, is_primary: true)

      get hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", drawer: "deposit")

      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).not_to include('data-testid="control-panel-action-drawer"')
    end

    it "renders only true editor drawers" do
      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", drawer: "deposit")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="control-panel-action-drawer"')
    end

    it "does not render removed billing drawer state" do
      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", drawer: "billing")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Billing Preferences")
      expect(response.body).not_to include('data-testid="control-panel-action-drawer"')
    end

    it "shows sibling child bookings when the booking belongs to a group" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "SIBLING-ROOM", reservation_number: 43)
      create(:booking_room, booking: booking, room_number: "103")
      create(:booking_room, booking: sibling, room_number: "104")

      get hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      child_nav = document.at_css('nav[aria-label="Group booking context"]')
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).to include("Bookings / Room Rate")
      expect(response.body).to include(hotel_booking_control_panel_path(hotel, sibling, tab: "room_and_rate"))
      expect(child_nav.text.squish).to include("In house Room 103")
      expect(child_nav.at_xpath('.//a[contains(normalize-space(), "Room")][1]')["data-turbo-frame"]).to eq("_top")
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

      get hotel_booking_control_panel_path(hotel, booking)

      expect(response).to have_http_status(:success)
      summary = Nokogiri::HTML(response.body).at_css('section[aria-label="Booking summary"]')
      expect(summary.at_xpath('.//button[normalize-space()="Actions"]')).to be_present
      expect(summary.css('a').map { |link| link.text.squish }).to include("Check-out")
      expect(summary.text).not_to include("Check-out...")
      expect(summary.text).not_to include("Checked out")
      checkout_action = summary.at_xpath('.//a[normalize-space()="Check-out"]')
      expect(checkout_action.at_css("svg")).to be_present
      expect(checkout_action["href"]).to include(hotel_booking_transaction_check_out_path(hotel, checkout_child))
      expect(checkout_action["data-turbo-frame"]).to eq("offcanvas_drawer")
      expect(checkout_action["data-offcanvas-variant"]).to eq("fullscreen-bottom")
    end

    it "renders group-aware actions on the group overview summary" do
      role.permissions << manage_bookings
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")

      get hotel_booking_control_panel_path(hotel, booking, scope: "group")

      expect(response).to have_http_status(:success)
      summary = Nokogiri::HTML(response.body).at_css('section[aria-label="Booking summary"]')
      expect(summary.at_xpath('.//button[normalize-space()="Actions"]')).to be_present
      expect(summary.css('a').map { |link| link.text.squish }).to include("Check-out")
      expect(summary.text).to include(group.name)
    end

    it "renders security deposits and requests with persistent standalone context" do
      create(:deposit, booking: booking, hotel: hotel, amount: 150, status: "held")
      create(:housekeeping_request, booking: booking, request_details: "Fresh towels")
      create(:complaint_request, booking: booking, complaint_details: "Noisy hallway")

      get hotel_booking_control_panel_path(hotel, booking, tab: "security_deposits")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).to include("Security Deposits")
      expect(response.body).to include("MYR 150.00")

      get hotel_booking_control_panel_path(hotel, booking, tab: "housekeeping_requests")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).to include("Fresh towels")
      expect(response.body).to include("Noisy hallway")
    end

    it "uses child-booking rails for grouped security deposits and requests" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      booking.update_column(:status, "checked_in")
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "SIBLING-REQ", reservation_number: 44)
      sibling.update_column(:status, "completed")
      create(:booking_room, booking: booking, room_number: "103")
      create(:booking_room, booking: sibling, room_number: "104")

      get hotel_booking_control_panel_path(hotel, booking, tab: "housekeeping_requests")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).to include("Bookings / Requests")
      expect(Nokogiri::HTML(response.body).text).to include("#{sibling.booking_rooms.first.room_type.name} - #{sibling.guest_name}")

      get hotel_booking_control_panel_path(hotel, booking, tab: "security_deposits")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).to include("Bookings / Deposits")
      deposit_document = Nokogiri::HTML(response.body)
      expect(deposit_document.text).to include("#{sibling.booking_rooms.first.room_type.name} - #{sibling.guest_name}")
      expect(deposit_document.at_css('nav[aria-label="Group booking context"]').text.squish).to include("In house Room 103", "Checked out Room 104")
    end

    it "renders overview and booking rows as chevron navigation without a group identity block" do
      group = create(:group_booking, hotel: hotel, name: "Hidden Group Name")
      booking.update!(group_booking: group, group_position: 1, guest_name: "Hanami Ume")
      room_type = create(:room_type, hotel: hotel, name: "Garden Prestige Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "105")

      get hotel_booking_control_panel_path(hotel, booking, tab: "booking_details", scope: "group")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      nav = document.at_css('nav[aria-label="Group booking context"]')
      links = nav.css("a")
      expect(links.map { |link| link.text.squish }).to include("Overview", "Confirmed Room 105 Garden Prestige Suite - Hanami Ume")
      expect(links).to all(satisfy { |link| link.at_css("svg").present? })
      expect(links.first["href"]).to include("tab=booking_details", "scope=group")
      expect(links.first["class"]).to include("bg-slate-900")
      expect(nav.text).not_to include(group.formatted_reservation_number, "Hidden Group Name")

      get hotel_booking_control_panel_path(hotel, booking, tab: "booking_details")
      child_document = Nokogiri::HTML(response.body)
      child_nav = child_document.at_css('nav[aria-label="Group booking context"]')
      summary = child_document.at_css('section[aria-label="Booking summary"]')
      expect(summary.text).to include("Booking No. #{group.formatted_reservation_number}")
      expect(summary.text).not_to include("Booking No. #{booking.formatted_reservation_number}")
      expect(child_nav.css("a").last["class"]).to include("bg-slate-900")
      expect(child_nav.css("a").first["class"]).not_to include("bg-slate-900")
      expect(child_nav.css("a").last["data-turbo-frame"]).to eq("_top")
    end

    it "renders functional group overviews across every tab" do
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
        "room_and_rate" => "Group Room &amp; Rate",
        "source_details" => "Group Source",
        "housekeeping_requests" => "Group overview towels",
        "audit_trails" => "Group Audit Trail"
      }

      expected_markers.each do |tab, marker|
        get hotel_booking_control_panel_path(hotel, booking, tab: tab, scope: "group")

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

    it "renders an Edit Stay launch link on the group overview booking details tab" do
      role.permissions << manage_bookings
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      get hotel_booking_control_panel_path(hotel, booking, tab: "booking_details", scope: "group")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      link = document.at_xpath("//a[normalize-space()='Edit Stay']")
      expect(link).to be_present
      expect(link["href"]).to eq(hotel_booking_transaction_amend_stay_path(hotel, booking))
    end

    it "hides the Edit Stay launch link on the group overview without manage_bookings permission" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)

      get hotel_booking_control_panel_path(hotel, booking, tab: "booking_details", scope: "group")

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_xpath("//a[normalize-space()='Edit Stay']")).to be_nil
    end

    it "redirects legacy grouped folio scope to the first child's primary folio" do
      group = create(:group_booking, hotel: hotel)
      later_child = booking
      later_child.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      fallback_folio = create(:booking_folio, :secondary, booking: first_child, hotel: hotel)
      primary_folio = create(:booking_folio, booking: first_child, hotel: hotel, is_primary: true)

      get hotel_booking_control_panel_path(hotel, later_child, tab: "folio_operations", scope: "group")

      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, first_child, tab: "folio_operations", folio_id: primary_folio.id))
      expect(response.location).not_to include("scope=group", "folio_id=#{fallback_folio.id}")
    end

    it "redirects grouped guest details to the first child's primary guest" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      create(:booking_guest, booking: first_child, guest: create(:guest), is_primary: false)
      primary_guest = create(:booking_guest, booking: first_child, guest: create(:guest), is_primary: true)

      get hotel_booking_control_panel_path(hotel, booking, tab: "guest_details")

      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, first_child, tab: "guest_details", booking_guest_id: primary_guest.id))
    end

    it "falls back to the first folio and guest when the first child has no primary entities" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      fallback_folio = create(:booking_folio, :secondary, booking: first_child, hotel: hotel, folio_sequence: 3)
      fallback_guest = create(:booking_guest, booking: first_child, guest: create(:guest), is_primary: false)

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations")
      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, first_child, tab: "folio_operations", folio_id: fallback_folio.id))

      get hotel_booking_control_panel_path(hotel, booking, tab: "guest_details")
      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, first_child, tab: "guest_details", booking_guest_id: fallback_guest.id))
    end

    it "renders the normal empty state when the first child has no folios" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 2)
      first_child = create(:booking, hotel: hotel, group_booking: group, group_position: 1)
      create(:booking_folio, booking: booking, hotel: hotel)

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations")
      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, first_child, tab: "folio_operations"))

      follow_redirect!
      expect(response).to have_http_status(:success)
      expect(response.body).to include("No folios are available.")
    end

    it "keeps explicit grouped entity selections canonical and removes synthetic overview links" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_folio, booking: booking, hotel: hotel)
      sibling_folio = create(:booking_folio, booking: sibling, hotel: hotel)

      get hotel_booking_control_panel_path(hotel, sibling, tab: "folio_operations", folio_id: sibling_folio.id)

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("aside").text).not_to include("Group Statement", "Group Guest Overview")
      expect(document.at_css("aside h2").text).to include("Bookings / Folios")
      expect(document.at_css('nav[aria-label="Bookings and folios"] a.bg-slate-900').text).to include(sibling_folio.display_name)
    end

    it "renders group deposits under group security deposits" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:group_deposit, group_booking: group, hotel: hotel, amount: 450, external_reference: "GROUP-DEP-450")

      get hotel_booking_control_panel_path(hotel, booking, tab: "security_deposits", scope: "group")

      expect(response).to have_http_status(:success)
      panel = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="security-deposits-heading"]')
      expect(panel.text).to include("Group Deposits", "GROUP-DEP-450", "MYR 450.00")
    end

    it "keeps group billing preferences focused on billing parties" do
      group = create(:group_booking, hotel: hotel, name: "Overview Group")
      booking.update!(group_booking: group, group_position: 1)
      create(:booking_guest, booking: booking, guest: create(:guest, name: "Child-only payer"), is_primary: true)

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", scope: "group")

      expect(response).to have_http_status(:success)
      panel = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="billing-preferences-heading"]')
      expect(panel.text).to include("Register billing parties", "Billing parties", "+ Add billing party", "Child-only payer")
      expect(panel.text).not_to include("Arrangement name", "+ Add arrangement")
    end

    it "renders a directed empty state for a booking without a room" do
      get hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No room is attached to this booking")
    end

    it "requires view booking permission" do
      role.permissions.delete(view_bookings)

      get hotel_booking_control_panel_path(hotel, booking)

      expect(response).to have_http_status(:redirect)
    end
  end
end
