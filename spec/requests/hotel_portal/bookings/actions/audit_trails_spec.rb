# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions::AuditTrails", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_bookings) { Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View Bookings" } }
  let(:audit_feature) { create(:feature, feature_group: create(:feature_group), slug: "full_audit_trail") }
  let(:booking) { create(:booking, hotel: hotel, confirmation_token: "BK-SHEET-42", reservation_number: 42, guest_name: "Fallback Name") }

  before do
    role.permissions << view_bookings
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
    hotel.update!(plan: create(:plan))
    create(:plan_feature, plan: hotel.plan, feature: audit_feature, enabled: true)
  end

  describe "GET /hotel/:hotel_id/booking-actions/audit-trail/:booking_id" do
    it "renders the booking audit timeline inside the booking_action_sheet frame" do
      create(:booking_audit_log, hotel: hotel, auditable: booking, user: user,
        old_value: { "status" => "pending" }, new_value: { "status" => "confirmed" })

      get hotel_booking_action_audit_trail_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      frame = document.at_css("turbo-frame#booking_action_sheet")
      expect(frame).to be_present
      dialog = frame.at_css("dialog[data-controller='panels-ui--sheet']")
      expect(dialog).to be_present
      expect(dialog["aria-label"]).to eq("Audit Trail")
      expect(dialog.text).to include("Audit Trail", "View Changes", "Pending", "Confirmed")
      # The Sheet supplies its own dismiss control, so the offcanvas close button is gone.
      expect(dialog.at_css('[data-action="click->offcanvas#close"]')).to be_nil
    end

    it "renders the simplified header with PanelsUI category and booking filters" do
      get hotel_booking_action_audit_trail_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      header = document.at_css("section[aria-labelledby='audit-history-heading'] header")
      tabs = document.at_css("#booking_action_sheet-audit-category-filter")
      booking_select = document.at_css("select[name='child_booking_id']")

      expect(header.text.squish).to eq("Audit Trail Important booking, stay, room, and financial changes.")
      expect(header.text).not_to include(booking.formatted_reservation_number, "of 0 events")
      expect(tabs["class"]).to include("tabs-root--pill")
      expect(tabs.css("a").map { |link| link.text.squish }).to eq([ "All", "Status", "Stay & Guest", "Rooms", "Financial", "Notes" ])
      expect(booking_select).to be_present
      expect(booking_select["disabled"]).to eq("disabled")
      expect(booking_select.css("option").size).to eq(1)
      expect(booking_select.at_css("option[selected]").text).to include(booking.formatted_reservation_number)
    end

    it "lists every group child and filters the audit trail to the selected child" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2)
      create(:booking_audit_log, hotel: hotel, auditable: booking, user: user,
        action_type: "status_change", category: "status",
        old_value: { "status" => "pending" }, new_value: { "status" => "confirmed" })
      create(:booking_audit_log, hotel: hotel, auditable: sibling, user: user,
        action_type: "status_change", category: "status",
        old_value: { "status" => "pending" }, new_value: { "status" => "cancelled" })

      get hotel_booking_action_audit_trail_path(hotel, booking)

      expect(response.body).to include("Booking moved to Confirmed", "Booking moved to Cancelled")
      document = Nokogiri::HTML(response.body)
      booking_select = document.at_css("select[name='child_booking_id']")
      expect(booking_select["disabled"]).to be_nil
      expect(booking_select.css("option").map { |option| option.text.squish }).to include(
        "All bookings",
        a_string_including(booking.formatted_reservation_number),
        a_string_including(sibling.formatted_reservation_number)
      )
      expect(booking_select.at_css("option[selected]").text).to eq("All bookings")

      get hotel_booking_action_audit_trail_path(hotel, booking, child_booking_id: booking.id)

      expect(response.body).to include("Booking moved to Confirmed")
      expect(response.body).not_to include("Booking moved to Cancelled")
      expect(Nokogiri::HTML(response.body).at_css("select[name='child_booking_id'] option[selected]").text).to include(booking.formatted_reservation_number)
    end

    it "filters by an allowlisted category and preserves scope in filter links" do
      group = create(:group_booking, hotel: hotel)
      booking.update!(group_booking: group, group_position: 1)
      create(:booking_audit_log, hotel: hotel, auditable: booking, user: user,
        action_type: "status_change", category: "status",
        old_value: { "status" => "pending" }, new_value: { "status" => "confirmed" })
      create(:booking_audit_log, hotel: hotel, auditable: booking, user: user,
        action_type: "note_added", category: "notes")

      get hotel_booking_action_audit_trail_path(hotel, booking, child_booking_id: booking.id, category: "notes")

      document = Nokogiri::HTML(response.body)
      expect(document.text).to include("Internal note added")
      expect(document.text).not_to include("Booking moved to Confirmed")
      status_link = document.css("#booking_action_sheet-audit-category-filter a").find { |link| link.text.squish == "Status" }
      expect(Rack::Utils.parse_query(URI(status_link["href"]).query)).to include("category" => "status", "child_booking_id" => booking.id.to_s)
      expect(document.at_css("#booking_action_sheet-audit-category-filter a[aria-current='page']").text.squish).to eq("Notes")
    end

    it "falls back to all categories for an invalid filter" do
      create(:booking_audit_log, hotel: hotel, auditable: booking, user: user, action_type: "note_added", category: "notes")

      get hotel_booking_action_audit_trail_path(hotel, booking, category: "forged")

      document = Nokogiri::HTML(response.body)
      expect(document.text).to include("Internal note added")
      expect(document.at_css("#booking_action_sheet-audit-category-filter a[aria-current='page']").text.squish).to eq("All")
    end

    it "distinguishes an empty filter from a booking with no audit history" do
      create(:booking_audit_log, hotel: hotel, auditable: booking, user: user, category: "status")

      get hotel_booking_action_audit_trail_path(hotel, booking, category: "notes")

      expect(response.body).to include("No events match these filters.")
      expect(response.body).not_to include("No audit history recorded.")
    end

    it "renders the empty audit state" do
      get hotel_booking_action_audit_trail_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("No audit history recorded.", "Important booking activity will appear here.")
    end

    it "does not render the full application layout" do
      get hotel_booking_action_audit_trail_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include("<!DOCTYPE html>")
    end

    it "blocks access when the audit feature is disabled" do
      hotel.plan.plan_features.find_by!(feature: audit_feature).update!(enabled: false)

      get hotel_booking_action_audit_trail_path(hotel, booking)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("This feature isn't included in your plan. Upgrade to access it.")
    end

    it "blocks access without view_bookings permission" do
      role.permissions.delete(view_bookings)

      get hotel_booking_action_audit_trail_path(hotel, booking)

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end

    it "does not expose another hotel's booking" do
      other_booking = create(:booking, hotel: other_hotel)

      get hotel_booking_action_audit_trail_path(hotel, other_booking)

      expect(response).to have_http_status(:not_found)
    end
  end
end
