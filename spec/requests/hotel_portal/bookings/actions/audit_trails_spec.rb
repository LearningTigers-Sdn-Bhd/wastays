# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions::AuditTrails", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
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
