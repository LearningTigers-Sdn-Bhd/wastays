# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions no-shows", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Garden Suite") }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      guest_name: "Ada Lovelace",
      status: "no_show_detected",
      no_show_detected_business_date: Date.current
    ).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: "101", subtotal: 200.0)
    end
  end

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def create_group_child(group, position:, room_number:, guest_name:)
    create(
      :booking,
      hotel: hotel,
      group_booking: group,
      group_position: position,
      status: "no_show_detected",
      no_show_detected_business_date: Date.current,
      guest_name: guest_name
    ).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: room_number, subtotal: 200.0)
    end
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission(role, "manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the mark-no-show form" do
    it "renders the no-show Sheet in the primary frame" do
      get hotel_booking_action_mark_no_show_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet dialog#booking-no-show-sheet[data-controller='panels-ui--sheet']")

      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Mark as no-show", "Ada Lovelace", "No-show reason")
      expect(dialog.at_css("textarea[name='no_show_reason'][required]")).to be_present
      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(response.body).not_to include("offcanvas")
    end

    it "describes what the hotel's no-show policy actually bills" do
      ReservationPolicies::EnsureDefaults.call(hotel)
      policy = hotel.hotel_reservation_policies.find_by!(policy_type: "no_show")

      policy.update!(rate_value: 2)
      get hotel_booking_action_mark_no_show_path(hotel, booking), headers: { "Turbo-Frame" => "booking_action_sheet" }
      expect(Nokogiri::HTML(response.body).at_css("dialog#booking-no-show-sheet").text)
        .to include("posts 2 nights of no-show room charges")

      policy.update!(active: false)
      get hotel_booking_action_mark_no_show_path(hotel, booking), headers: { "Turbo-Frame" => "booking_action_sheet" }
      expect(Nokogiri::HTML(response.body).at_css("dialog#booking-no-show-sheet").text)
        .to include("posts no no-show charge")
    end

    it "renders the group target selector for a group booking" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      get hotel_booking_action_mark_no_show_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("dialog#booking-no-show-sheet")
      expect(dialog.css("input[name='booking_ids[]']")).not_to be_empty
      expect(dialog.at_css("input[name='target_scope']")).to be_present
    end

    it "renders into the secondary frame when launched stacked" do
      get hotel_booking_action_mark_no_show_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-no-show-sheet")).to be_present
    end
  end

  describe "POST the mark-no-show" do
    it "finalizes the no-show and completes the sheet on a Turbo submission" do
      post hotel_booking_action_mark_no_show_path(hotel, booking),
        params: { no_show_reason: "Guest did not arrive" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(response.body).to include(CGI.escapeHTML(hotel_booking_workspace_path(hotel, booking, tab: "booking_details")))
      expect(booking.reload.status).to eq("no_show")
    end

    it "redirects to the control panel on a direct request" do
      post hotel_booking_action_mark_no_show_path(hotel, booking),
        params: { no_show_reason: "Guest did not arrive" }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(flash[:notice]).to include("Booking marked as no-show.")
      expect(booking.reload.status).to eq("no_show")
      expect(BookingAuditLog.where(auditable: booking, action_type: "no_show").last.metadata).to include(
        "reason" => "Guest did not arrive"
      )
    end

    it "keeps the sheet open with an error when the reason is blank" do
      post hotel_booking_action_mark_no_show_path(hotel, booking),
        params: { no_show_reason: "" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("dialog", "No-show reason is required.")
      expect(booking.reload.status).to eq("no_show_detected")
    end

    it "completes into the secondary frame when submitted stacked" do
      post hotel_booking_action_mark_no_show_path(hotel, booking),
        params: { no_show_reason: "Guest did not arrive" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="booking_action_sheet_secondary"')
      expect(booking.reload.status).to eq("no_show")
    end

    it "closes the sheet with a flash alert when the booking is not pending no-show review" do
      confirmed = create(:booking, hotel: hotel, status: "confirmed")
      create(:booking_room, booking: confirmed, room_type: room_type, room_number: "102", subtotal: 200.0)

      post hotel_booking_action_mark_no_show_path(hotel, confirmed),
        params: { no_show_reason: "Too soon" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:alert]).to eq("Booking is not waiting for a no-show decision.")
      expect(confirmed.reload.status).to eq("confirmed")
    end

    it "batch-marks the selected group bookings as no-show" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      post hotel_booking_action_mark_no_show_path(hotel, booking),
        params: { no_show_reason: "Group no-show", target_scope: "group", booking_ids: [ booking.id, sibling.id ] },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:notice]).to eq("2 bookings marked as no-show.")
      expect(booking.reload.status).to eq("no_show")
      expect(sibling.reload.status).to eq("no_show")
    end

    it "blocks marking no-show without manage_bookings permission" do
      role.role_permissions.destroy_all

      post hotel_booking_action_mark_no_show_path(hotel, booking),
        params: { no_show_reason: "Guest did not arrive" }

      expect(response).to have_http_status(:redirect)
      expect(booking.reload.status).to eq("no_show_detected")
    end

    it "does not find a booking from another hotel" do
      other_booking = create(:booking, hotel: other_hotel, status: "no_show_detected", no_show_detected_business_date: Date.current)

      post hotel_booking_action_mark_no_show_path(hotel, other_booking),
        params: { no_show_reason: "Guest did not arrive" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
