# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions booking overviews", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:view_bookings) { Permission.find_or_create_by!(slug: "view_bookings") { |permission| permission.name = "View Bookings" } }
  let(:manage_bookings) { Permission.find_or_create_by!(slug: "manage_bookings") { |permission| permission.name = "Manage Bookings" } }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Garden Suite") }
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      confirmation_token: "SUMMARY-42",
      reservation_number: 42,
      guest_name: "Ada Lovelace",
      total_amount: 480,
      status: "confirmed"
    ).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: "101")
    end
  end

  before do
    role.permissions << view_bookings
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET booking summary" do
    it "renders the standalone summary in the shared Sheet frame" do
      get hotel_booking_action_show_booking_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      frame = document.at_css("turbo-frame#booking_action_sheet")
      dialog = frame.at_css("dialog#booking-summary-sheet")

      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog["class"]).to include("w-[36rem]")
      expect(dialog.text).to include("Ada Lovelace", "Booking No.", "Stay summary", booking.formatted_reservation_number, "Garden Suite", "MYR 480.00")
      expect(dialog.text).to include("Actions", "Booking Control Panel", "Receipt", "Resend Confirmation")
      expect(dialog.text).not_to include("Guest Registration Card")
      control_labels = dialog.css("a, button").map { |control| control.text.squish }
      expect(control_labels).to include("Actions")
      expect(control_labels).not_to include("Check-in", "Cancel booking")
      expect(response.body).not_to include("<!DOCTYPE html>")
    end

    it "launches Cancel into the secondary frame so it stacks over the summary" do
      role.permissions << manage_bookings

      get hotel_booking_action_show_booking_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      summary = document.at_css("dialog#booking-summary-sheet")
      cancel = summary.css("a").find { |candidate| candidate.text.squish.include?("Cancel booking") }

      expect(cancel).to be_present
      expect(URI.parse(cancel["href"]).path).to eq(hotel_booking_action_cancel_booking_path(hotel, booking))
      # Targeting the secondary frame is the knob that stacks the cancellation.
      expect(cancel["data-turbo-frame"]).to eq("booking_action_sheet_secondary")
    end

    it "launches Check-in from the Actions dropdown into the secondary frame" do
      role.permissions << manage_bookings

      get hotel_booking_action_show_booking_path(hotel, booking, source: "stay_view", return_to: hotel_stay_view_path(hotel))

      summary = Nokogiri::HTML(response.body).at_css("dialog#booking-summary-sheet")
      check_in = summary.css("a").find { |candidate| candidate.text.squish == "Check-in" }
      uri = URI.parse(check_in["href"])

      expect(uri.path).to eq(hotel_booking_action_check_in_path(hotel, booking))
      expect(Rack::Utils.parse_nested_query(uri.query)).to include("source" => "stay_view", "return_to" => hotel_stay_view_path(hotel))
      expect(check_in["data-turbo-frame"]).to eq("booking_action_sheet_secondary")
    end

    it "launches intent-scoped stay-editing actions into the secondary frame" do
      role.permissions << manage_bookings

      get hotel_booking_action_show_booking_path(hotel, booking, source: "stay_view", return_to: hotel_stay_view_path(hotel))

      summary = Nokogiri::HTML(response.body).at_css("dialog#booking-summary-sheet")
      edit_dates = summary.css("a").find { |candidate| candidate.text.squish == "Edit dates" }
      uri = URI.parse(edit_dates["href"])

      expect(uri.path).to eq(hotel_booking_action_edit_dates_path(hotel, booking))
      expect(Rack::Utils.parse_nested_query(uri.query)).to include("source" => "stay_view", "return_to" => hotel_stay_view_path(hotel))
      expect(Rack::Utils.parse_nested_query(uri.query)).not_to have_key("proposal")
      expect(edit_dates["data-turbo-frame"]).to eq("booking_action_sheet_secondary")

      labels = summary.css("a").map { |anchor| anchor.text.squish }
      expect(labels).to include("Edit dates", "Change room", "Change rate")
    end

    it "hides Cancel from users without manage_bookings" do
      get hotel_booking_action_show_booking_path(hotel, booking)

      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-summary-sheet")
      expect(dialog.css("a").map { |anchor| anchor.text.squish }).not_to include("Cancel booking")
      expect(dialog.css("a").map { |anchor| anchor.text.squish }).not_to include("Edit dates")
    end

    it "shows management-only document actions to booking managers" do
      role.permissions << manage_bookings
      booking.update!(guest_country: "Singapore", tourism_tax_amount: 20, tourism_tax_applied: true,
        tax_lines: [ { "type" => "tourism_tax", "amount" => 20 } ])

      get hotel_booking_action_show_booking_path(hotel, booking)

      expect(response.body).to include("Guest Registration Card", "Issue Tourism Tax Voucher")
      expect(response.body).to include(issue_hotel_booking_tourism_tax_voucher_path(hotel, booking))
    end

    it "omits the tourism tax voucher when the booking has no tourism tax" do
      role.permissions << manage_bookings

      get hotel_booking_action_show_booking_path(hotel, booking)

      expect(response.body).not_to include("Tourism Tax Voucher")
    end

    it "renders a group summary that launches Print / Send into the secondary frame" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, guest_name: "Grace Hopper")
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")
      return_to = hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      get hotel_booking_action_show_booking_path(hotel, booking, source: "stay_view", return_to: return_to)

      document = Nokogiri::HTML(response.body)
      summary = document.at_css("turbo-frame#booking_action_sheet dialog#booking-summary-sheet")
      link = summary.css("a").find { |candidate| candidate.text.squish == "Print / Send" }
      uri = URI.parse(link["href"])

      expect(summary.text).to include("Conference Group", "Group reservation", "2 rooms")
      expect(uri.path).to eq(hotel_booking_action_group_print_send_path(hotel, booking))
      expect(Rack::Utils.parse_nested_query(uri.query)).to eq("source" => "stay_view", "return_to" => return_to)
      # Targeting the secondary frame is the knob that makes the documents sheet stack.
      expect(link["data-turbo-frame"]).to eq("booking_action_sheet_secondary")

      # The documents sheet is its own lazy action, not inlined into the summary.
      expect(document.at_css("dialog#booking-group-documents-sheet")).to be_nil
    end

    it "blocks missing permission and bookings from another hotel" do
      role.permissions.delete(view_bookings)

      get hotel_booking_action_show_booking_path(hotel, booking)
      expect(response).to redirect_to(root_path)

      role.permissions << view_bookings
      other_booking = create(:booking, hotel: other_hotel)
      get hotel_booking_action_show_booking_path(hotel, other_booking)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET group Print / Send documents" do
    let(:group) { create(:group_booking, hotel: hotel) }

    before { booking.update!(group_booking: group, group_position: 1) }

    it "renders the documents into the secondary frame so it stacks above the summary" do
      role.permissions << manage_bookings
      completed = create(
        :booking,
        hotel: hotel,
        group_booking: group,
        group_position: 2,
        status: "completed",
        confirmation_token: "GROUP-COMPLETE",
        guest_name: "Grace Hopper"
      )
      create(:booking_room, booking: completed, room_type: room_type, room_number: "102")

      get hotel_booking_action_group_print_send_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-group-documents-sheet")

      expect(dialog).to be_present
      expect(dialog.text).to include("Group documents", "Garden Suite (2)", "101", "102", "Grace Hopper")
      expect(dialog.text).to include("Group Receipt", "Group Invoice", "Resend Group Confirmation", "Unavailable")
      expect(dialog.text).to include("Registration card", "Resend confirmation", "Resend pre-check-in")
      expect(dialog.at_css("a[href='#{receipt_booking_path(completed.confirmation_token)}'][target='_blank'][data-turbo='false']")).to be_present
      expect(dialog.at_css("a[href='#{invoice_booking_path(completed.confirmation_token)}'][target='_blank'][data-turbo='false']")).to be_present
      expect(dialog.at_css("a[href='#{invoice_booking_path(booking.confirmation_token)}']")).to be_nil
    end

    it "opens standalone in the primary frame when launched on its own" do
      get hotel_booking_action_group_print_send_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet dialog#booking-group-documents-sheet")).to be_present
    end

    it "closes through the native sheet stack rather than navigating back" do
      get hotel_booking_action_group_print_send_path(hotel, booking)

      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("dialog#booking-group-documents-sheet")
      back = dialog.css("button").find { |candidate| candidate.text.squish == "Back to booking summary" }
      expect(back["data-action"]).to eq("panels-ui--sheet#close")
    end

    it "redirects a standalone (non-group) booking back to its summary" do
      standalone = create(:booking, hotel: hotel)
      return_to = hotel_stay_view_path(hotel)

      get hotel_booking_action_group_print_send_path(hotel, standalone, source: "stay_view", return_to: return_to)

      expect(response).to redirect_to(hotel_booking_action_show_booking_path(hotel, standalone, source: "stay_view", return_to: return_to))
      expect(flash[:alert]).to eq("Print / Send group view is only available for group bookings.")
    end
  end
end
