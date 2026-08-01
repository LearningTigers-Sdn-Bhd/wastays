# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions review-backdated check-ins", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Garden Suite") }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      guest_name: "Ada Lovelace",
      status: "no_show_detected",
      no_show_detected_business_date: Date.current,
      check_in: Date.current,
      check_out: Date.current + 1.day
    ).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: "101", subtotal: 100.0)
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
      check_in: Date.current,
      check_out: Date.current + 1.day,
      guest_name: guest_name
    ).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: room_number, subtotal: 100.0)
    end
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission(role, "manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the backdated-check-in form" do
    it "renders the backdated Sheet in the primary frame" do
      get hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet dialog#review-backdated-check-in-sheet[data-controller='panels-ui--sheet']")

      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Backdated check-in", "Ada Lovelace", "Backdate reason")
      expect(dialog.at_css("select[name='backdate_reason']")).to be_present
      expect(dialog.at_css("input[name='booking[checked_in_at]']")).to be_present
      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders the group target selector for a group booking" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      get hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("dialog#review-backdated-check-in-sheet")
      expect(dialog.css("input[name='booking_ids[]']")).not_to be_empty
      expect(dialog.at_css("input[name='target_scope']")).to be_present
    end

    it "renders into the secondary frame when launched stacked" do
      get hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#review-backdated-check-in-sheet")).to be_present
    end
  end

  describe "POST the backdated-check-in" do
    it "checks the booking in and completes the sheet on a Turbo submission" do
      post hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        params: { booking: { checked_in_at: Time.current }, retroactive_reason: "Late arrival" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(booking.reload.status).to eq("checked_in")
    end

    it "redirects to the control panel on a direct request" do
      post hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        params: { booking: { checked_in_at: Time.current }, retroactive_reason: "Late arrival" }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(flash[:notice]).to eq("Backdated check-in completed.")
      expect(booking.reload.status).to eq("checked_in")
    end

    it "accepts a standard category with blank reason details" do
      post hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        params: { booking: { checked_in_at: Time.current }, backdate_reason: "System / internet issue", retroactive_reason: "" }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(booking.reload.status).to eq("checked_in")
    end

    it "keeps the sheet open when Other is chosen without details" do
      post hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        params: { booking: { checked_in_at: Time.current }, backdate_reason: "Other", retroactive_reason: "" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("dialog", "Please provide details for the backdated check-in reason.")
      expect(booking.reload.status).to eq("no_show_detected")
    end

    it "keeps the sheet open when no reason is provided" do
      post hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        params: { booking: { checked_in_at: Time.current }, backdate_reason: "", retroactive_reason: "" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("dialog", "Backdated check-in reason is required.")
      expect(booking.reload.status).to eq("no_show_detected")
    end

    it "closes the sheet with a flash alert when the booking is not under no-show review" do
      confirmed = create(:booking, hotel: hotel, status: "confirmed")
      create(:booking_room, booking: confirmed, room_type: room_type, room_number: "102", subtotal: 100.0)

      post hotel_booking_action_review_backdated_check_in_path(hotel, confirmed),
        params: { booking: { checked_in_at: Time.current }, retroactive_reason: "Late arrival" },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:alert]).to eq("Backdated check-in is only available while reviewing a missed arrival.")
      expect(confirmed.reload.status).to eq("confirmed")
    end

    it "batch-backdates the selected group bookings" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      post hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        params: { booking: { checked_in_at: Time.current }, retroactive_reason: "Group late arrival", target_scope: "group", booking_ids: [ booking.id, sibling.id ] },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:notice]).to eq("2 bookings backdated checked in.")
      expect(booking.reload.status).to eq("checked_in")
      expect(sibling.reload.status).to eq("checked_in")
    end

    it "blocks backdated check-in without manage_bookings permission" do
      role.role_permissions.destroy_all

      post hotel_booking_action_review_backdated_check_in_path(hotel, booking),
        params: { booking: { checked_in_at: Time.current }, retroactive_reason: "Late arrival" }

      expect(response).to have_http_status(:redirect)
      expect(booking.reload.status).to eq("no_show_detected")
    end

    it "does not find a booking from another hotel" do
      other_booking = create(:booking, hotel: other_hotel, status: "no_show_detected", no_show_detected_business_date: Date.current)

      post hotel_booking_action_review_backdated_check_in_path(hotel, other_booking),
        params: { booking: { checked_in_at: Time.current }, retroactive_reason: "Late arrival" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
