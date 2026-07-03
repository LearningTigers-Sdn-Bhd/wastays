# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::BookingControlPanels", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_bookings) { Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View Bookings" } }
  let(:manage_folio_windows) { Permission.find_or_create_by!(slug: "manage_folio_windows") { |permission| permission.name = "Manage Folio Windows" } }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      confirmation_token: "BK-PANEL-42",
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
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208", quantity: 1)

      get hotel_booking_control_panel_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Booking control panel")
      expect(response.body).to include("BK-PANEL-42")
      expect(response.body).to include("Aina Rahman")
      expect(response.body).to include("Garden Suite")
      expect(response.body).to include("208")
      expect(response.body).to include("Direct")
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

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", folio_id: target_folio.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("PRIVATE ROUTE MARKER")
      expect(response.body).to include("Billing Instructions")
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
      expect(response.body).to include("Billing Instructions")
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
      folio = create(:booking_folio, booking: booking, hotel: hotel, name: "Guest Folio")

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations", folio_id: folio.id)

      folio_document = Nokogiri::HTML(response.body)
      folio_nav = folio_document.at_css('nav[aria-label="Booking folios"]')
      folio_summary = folio_nav.at_css("details[open] summary")
      expect(folio_summary.text).to include(booking.confirmation_token)
      expect(folio_summary.text).not_to include(guest.name)
      expect(folio_summary.at_css('.group-open\\:rotate-90')).to be_present
      expect(folio_nav.at_css("a.bg-slate-900").text).to include(folio.display_name)
      expect(folio_nav.to_html).not_to include("border-l-2")

      get hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id)

      guest_document = Nokogiri::HTML(response.body)
      guest_nav = guest_document.at_css('nav[aria-label="Booking guests"]')
      guest_summary = guest_nav.at_css("details[open] summary")
      expect(guest_summary.text).to include(booking.confirmation_token)
      expect(guest_summary.text).not_to include(guest.name)
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

    it "opens only the current booking in grouped entity rails" do
      allow(BookingRedesign).to receive(:enabled?).and_return(true)
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "COLLAPSED-SIBLING")
      create(:booking_room, booking: booking, room_number: "101")
      create(:booking_room, booking: sibling, room_number: "102")
      create(:booking_folio, booking: booking, hotel: hotel, name: "Current Folio")
      create(:booking_folio, booking: sibling, hotel: hotel, name: "Sibling Folio")

      get hotel_booking_control_panel_path(hotel, booking, tab: "folio_operations")

      document = Nokogiri::HTML(response.body)
      details = document.at_css('nav[aria-label="Group bookings and folios"]').css("details")
      expect(details.size).to eq(2)
      expect(details.first.key?("open")).to be(true)
      expect(details.last.key?("open")).to be(false)
      expect(details.first.at_css("summary").text).not_to include(booking.guest_name)
      expect(details.last.at_css("summary").text).not_to include(sibling.guest_name)
    end

    it "does not allow access to another hotel's booking" do
      other_booking = create(:booking, hotel: other_hotel)

      get hotel_booking_control_panel_path(hotel, other_booking)

      expect(response).to have_http_status(:not_found)
    end

    it "renders every control panel tab with its declared layout" do
      guest = create(:guest, name: "Aina Rahman")
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      room = create(:booking_room, booking: booking, room_type: room_type, room_number: "208", quantity: 1)
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

    it "renders only the workspace frame for workspace turbo requests" do
      room_type = create(:room_type, hotel: hotel, name: "Garden Suite")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "208", quantity: 1)

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

    it "renders rate and routing warnings as alert dialogs without widening the workspace" do
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
      expect(response.body).to include("Apply routing change?")
      expect(response.body).to include("existing_and_future")
    end

    it "opens room and guest editors directly in the offcanvas" do
      guest = create(:booking_guest, booking: booking, is_primary: true)
      create(:booking_room, booking: booking)

      get hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")
      document = Nokogiri::HTML(response.body)
      change_room = document.at_xpath("//a[normalize-space()='Change Room']")
      expect(change_room["data-turbo-frame"]).to eq("offcanvas_drawer")
      expect(change_room["href"]).to eq(hotel_booking_transaction_edit_booking_timeline_path(hotel, booking))

      get hotel_booking_control_panel_path(hotel, booking, tab: "guest_details", booking_guest_id: guest.id)
      document = Nokogiri::HTML(response.body)
      expect(document.at_xpath("//a[normalize-space()='Add Guest']")["data-turbo-frame"]).to eq("offcanvas_drawer")
      expect(document.at_xpath("//a[normalize-space()='Edit Guest']")["data-turbo-frame"]).to eq("offcanvas_drawer")
    end

    it "renders only true editor drawers" do
      drawer_tabs = {
        "billing" => "billing_preferences",
        "deposit" => "folio_operations"
      }

      drawer_tabs.each do |drawer, tab|
        get hotel_booking_control_panel_path(hotel, booking, tab: tab, drawer: drawer)

        expect(response).to have_http_status(:success), "expected #{drawer} drawer to render"
        expect(response.body).to include('data-testid="control-panel-action-drawer"')
      end
    end

    it "shows sibling child bookings only when grouped UI is enabled" do
      allow(BookingRedesign).to receive(:enabled?).and_return(true)
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "SIBLING-ROOM")
      create(:booking_room, booking: booking)
      create(:booking_room, booking: sibling)

      get hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).to include("SIBLING-ROOM")
      expect(response.body).to include("Group Booking")
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
      allow(BookingRedesign).to receive(:enabled?).and_return(true)
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "SIBLING-REQ")
      create(:booking_room, booking: booking)
      create(:booking_room, booking: sibling)

      get hotel_booking_control_panel_path(hotel, booking, tab: "housekeeping_requests")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).to include("SIBLING-REQ")

      get hotel_booking_control_panel_path(hotel, booking, tab: "security_deposits")
      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-layout-mode="left_and_center"')
      expect(response.body).to include("SIBLING-REQ")
    end

    it "renders functional group overviews across every tab" do
      allow(BookingRedesign).to receive(:enabled?).and_return(true)
      group = create(:group_booking, hotel: hotel, reference: "GROUP-OVERVIEW", name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, confirmation_token: "GROUP-CHILD-2")
      [ booking, sibling ].each_with_index do |child, index|
        room = create(:booking_room, booking: child, room_number: "20#{index + 1}")
        create(:booking_guest, booking: child, guest: create(:guest, name: "Group Guest #{index + 1}"), is_primary: true)
        create(:booking_folio, booking: child, hotel: hotel, booking_room: room, name: "Guest Folio #{index + 1}")
      end
      create(:deposit, booking: sibling, hotel: hotel, amount: 200, status: "held")
      create(:housekeeping_request, booking: sibling, request_details: "Group overview towels")

      expected_markers = {
        "booking_details" => "Conference Group",
        "folio_operations" => "Group Statement",
        "security_deposits" => "GROUP-CHILD-2",
        "billing_preferences" => "Default payers and settlement methods for the group",
        "guest_details" => "Group Guest 2",
        "room_and_rate" => "Group Room &amp; Rate",
        "source_details" => "Group Source",
        "housekeeping_requests" => "Group overview towels",
        "audit_trails" => "Group Audit Trail"
      }

      expected_markers.each do |tab, marker|
        get hotel_booking_control_panel_path(hotel, booking, tab: tab, scope: "group")

        expect(response).to have_http_status(:success), "expected group overview for #{tab}"
        expect(response.body).to include(marker)
        expect(response.body).to include("GROUP-OVERVIEW")
        if tab == "room_and_rate"
          table = Nokogiri::HTML(response.body).at_css('section[aria-labelledby="room-rate-heading"] table')
          expect(table.css("thead th").map { |header| header.text.strip }).to eq([ "Booking", "Stay Date", "Room Type", "Room", "Rate Plan", "Nightly Rate" ])
          expect(table.text).not_to include("Guest", "Status", "Estimated Room Value")
        end
      end
    end

    it "renders group arrangement creation inline" do
      allow(BookingRedesign).to receive(:enabled?).and_return(true)
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      corporate_account = create(:account, :corporate, name: "Group Account")
      create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_account)

      get hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences", scope: "group", billing_editor: "new_arrangement")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Arrangement name", "Group Account", "Default coverage", "Create arrangement")
      expect(Nokogiri::HTML(response.body).at_css("form[action*='create_group_billing_arrangement']")).to be_present
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

    it "leaves the legacy booking and folio pages reachable" do
      create(:booking_folio, booking: booking, hotel: hotel)

      get hotel_booking_path(hotel, booking)
      expect(response).to have_http_status(:success)

      get hotel_folio_path(hotel, booking)
      expect(response).to have_http_status(:success)
    end
  end
end
