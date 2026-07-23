# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions undo check-ins", :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Garden Suite") }
  let(:booking) do
    create(:booking, hotel: hotel, guest_name: "Ada Lovelace", status: "checked_in").tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: "101")
    end
  end

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def create_group_child(group, position:, room_number:, guest_name:, status: "checked_in")
    create(:booking, hotel: hotel, group_booking: group, group_position: position, status: status, guest_name: guest_name).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: room_number)
    end
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission(role, "manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the undo-check-in form" do
    it "renders the undo Sheet in the primary frame" do
      get hotel_booking_action_undo_check_in_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet dialog#booking-undo-check-in-sheet[data-controller='panels-ui--sheet']")

      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Undo check-in", "Ada Lovelace", "Reason to change")
      expect(dialog.at_css("input[name='retroactive_reason'][required]")).to be_present
      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders into the secondary frame when launched stacked" do
      get hotel_booking_action_undo_check_in_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-undo-check-in-sheet")).to be_present
    end
  end

  describe "POST the undo-check-in" do
    it "reverts the booking to confirmed and completes the sheet on a Turbo submission" do
      post hotel_booking_action_undo_check_in_path(hotel, booking),
        params: { retroactive_reason: "Checked in by mistake" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(booking.reload.status).to eq("confirmed")
    end

    it "redirects to the control panel on a direct request" do
      post hotel_booking_action_undo_check_in_path(hotel, booking),
        params: { retroactive_reason: "Checked in by mistake" }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(flash[:notice]).to eq("Check-in undone successfully.")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "keeps the sheet open with an error when the reason is blank" do
      post hotel_booking_action_undo_check_in_path(hotel, booking),
        params: { retroactive_reason: "" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("dialog", "Reason to change is required.")
      expect(booking.reload.status).to eq("checked_in")
    end

    it "completes into the secondary frame when submitted stacked" do
      post hotel_booking_action_undo_check_in_path(hotel, booking),
        params: { retroactive_reason: "Checked in by mistake" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="booking_action_sheet_secondary"')
      expect(booking.reload.status).to eq("confirmed")
    end

    it "closes the sheet with a flash alert when the booking is not checked in" do
      confirmed = create(:booking, hotel: hotel, status: "confirmed")
      create(:booking_room, booking: confirmed, room_type: room_type, room_number: "102")

      post hotel_booking_action_undo_check_in_path(hotel, confirmed),
        params: { retroactive_reason: "Wrong booking" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:alert]).to eq("Undo check-in is only available for checked-in bookings.")
      expect(confirmed.reload.status).to eq("confirmed")
    end

    it "batch-undoes the selected group check-ins" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      post hotel_booking_action_undo_check_in_path(hotel, booking),
        params: { retroactive_reason: "Batch revert", target_scope: "group", booking_ids: [ booking.id, sibling.id ] },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:notice]).to eq("2 bookings check-in undone.")
      expect(booking.reload.status).to eq("confirmed")
      expect(sibling.reload.status).to eq("confirmed")
    end

    it "blocks undo without manage_bookings permission" do
      role.role_permissions.destroy_all

      post hotel_booking_action_undo_check_in_path(hotel, booking),
        params: { retroactive_reason: "Checked in by mistake" }

      expect(response).to have_http_status(:redirect)
      expect(booking.reload.status).to eq("checked_in")
    end

    it "does not find a booking from another hotel" do
      other_booking = create(:booking, hotel: other_hotel, status: "checked_in")

      post hotel_booking_action_undo_check_in_path(hotel, other_booking),
        params: { retroactive_reason: "Checked in by mistake" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
