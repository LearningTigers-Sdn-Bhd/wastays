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
      expect(dialog.text).to include("Manage Booking", "Print/Send")
      expect(dialog.text).not_to include("Guest Registration Card")
      control_labels = dialog.css("a, button").map { |control| control.text.squish }
      expect(control_labels).to include("Manage Booking", "Print/Send")
      # Nothing is actionable without manage_bookings, so the overflow menu stays hidden.
      expect(control_labels).not_to include("More Actions", "Check-in", "Cancel booking")
      expect(response.body).not_to include("<!DOCTYPE html>")
    end

    it "lists the primary guest's boat slots beside arrival and departure" do
      boat_in = booking.check_in + 2.hours
      boat_out = booking.check_out + 3.hours
      create(:booking_guest, booking: booking, is_primary: true, boat_in_at: boat_in, boat_out_at: boat_out)

      get hotel_booking_action_show_booking_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-summary-sheet")
      expect(dialog.text).to include("Boat-in", "Boat-out")
      expect(dialog.text).to include(
        boat_in.in_time_zone(hotel.hotel_time_zone).strftime("%Y/%m/%d %H:%M"),
        boat_out.in_time_zone(hotel.hotel_time_zone).strftime("%Y/%m/%d %H:%M")
      )
    end

    it "omits the boat slots when the property does not run transfers" do
      hotel.update!(allow_boat_information: false)

      get hotel_booking_action_show_booking_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      dialog = Nokogiri::HTML(response.body).at_css("dialog#booking-summary-sheet")
      expect(dialog.text).not_to include("Boat-in", "Boat-out")
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

      get hotel_booking_action_group_print_send_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response.body).to include("Registration Card", "Tourism Tax Voucher")
      expect(response.body).to include(issue_hotel_booking_tourism_tax_voucher_path(hotel, booking))
    end

    it "omits the tourism tax voucher when the booking has no tourism tax" do
      role.permissions << manage_bookings

      get hotel_booking_action_group_print_send_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response.body).not_to include("Tourism Tax Voucher")
    end

    it "renders a group summary that opens Print/Send in the secondary sheet" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: hotel, group_booking: group, group_position: 2, guest_name: "Grace Hopper")
      create(:booking_room, booking: sibling, room_type: room_type, room_number: "102")
      return_to = hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7)

      get hotel_booking_action_show_booking_path(hotel, booking, source: "stay_view", return_to: return_to)

      document = Nokogiri::HTML(response.body)
      summary = document.at_css("turbo-frame#booking_action_sheet dialog#booking-summary-sheet")
      link = summary.css("a").find { |candidate| candidate.text.squish == "Print/Send" }
      uri = URI.parse(link["href"])

      expect(summary.text).to include("Conference Group", "Group reservation", "2 rooms")
      expect(uri.path).to eq(hotel_booking_action_group_print_send_path(hotel, booking))
      expect(link["data-turbo-frame"]).to eq("booking_action_sheet_secondary")
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

  describe "GET Print/Send" do
    let(:group) { create(:group_booking, hotel: hotel) }

    before { booking.update!(group_booking: group, group_position: 1) }

    it "renders group shortcuts without loading catalog counts" do
      get hotel_booking_action_group_print_send_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet_secondary dialog#quick-documents-sheet")
      expect(dialog.text).to include("Print/Send", "Open the Documents tab", "consolidated statements", "View all documents")
      expect(dialog.text).not_to include("Invoices 0", "Receipts 0", "Registration cards 0")
      expect(dialog.text).not_to include("Room 101")
    end

    it "renders standalone document shortcuts" do
      standalone = create(:booking, hotel: hotel)

      get hotel_booking_action_group_print_send_path(hotel, standalone)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Print/Send", "Invoice", "Receipt", "Registration Card", "View all documents")
    end
  end

  describe "POST Print/Send resend" do
    before do
      folio = create(:booking_folio, booking:, hotel:, status: "closed")
      Invoices::Finalize.call!(folio:, issued_by: nil, balance: 0)
    end

    it "requires manage_bookings" do
      post hotel_booking_action_group_print_send_resend_path(hotel, booking)

      expect(response).to redirect_to(root_path)
      expect(NotificationDelivery.where(notification_type: "invoice_package")).to be_empty
    end

    it "discovers eligible invoices and queues one combined delivery" do
      role.permissions << manage_bookings

      expect do
        post hotel_booking_action_group_print_send_resend_path(hotel, booking),
          params: { return_to: hotel_booking_workspace_path(hotel, booking, tab: "documents") }
      end.to change { NotificationDelivery.where(notification_type: "invoice_package").count }.by(1)

      delivery = NotificationDelivery.where(notification_type: "invoice_package").last
      expect(delivery.payload["invoice_ids"]).to eq([ booking.booking_folios.first.invoice.id ])
      expect(delivery.payload["source"]).to eq("manual_resend")
      expect(delivery.payload["requested_by_id"]).to eq(user.id)
      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "documents"))
    end
  end
end
