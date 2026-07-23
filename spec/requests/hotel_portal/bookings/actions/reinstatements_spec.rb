# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions reinstatements", :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Garden Suite", room_number_mode: "custom", room_numbers: %w[101 102 103]) }
  let(:booking) do
    create(:booking, hotel: hotel, guest_name: "Ada Lovelace", status: "no_show", check_in: Date.current, check_out: Date.current + 1.day).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: "101")
    end
  end

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def create_group_child(group, position:, room_number:, guest_name:)
    create(:booking, hotel: hotel, group_booking: group, group_position: position, status: "no_show", guest_name: guest_name, check_in: Date.current, check_out: Date.current + 1.day).tap do |record|
      create(:booking_room, booking: record, room_type: room_type, room_number: room_number)
    end
  end

  def stub_reinstate_reservation(success:, error: nil)
    instance_double(Bookings::ReinstateReservation, call: OpenStruct.new(success?: success, error: error)).tap do |service|
      allow(Bookings::ReinstateReservation).to receive(:new).and_return(service)
    end
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel: hotel, date: Date.current)
    grant_permission(role, "manage_bookings")
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the reinstate form" do
    it "renders the reinstate Sheet with per-room selectors in the primary frame" do
      get hotel_booking_action_reinstate_no_show_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("turbo-frame#booking_action_sheet dialog#booking-reinstate-sheet[data-controller='panels-ui--sheet']")

      expect(dialog).to be_present
      expect(dialog["data-panels-ui-sheet-side"]).to eq("right")
      expect(dialog.text).to include("Reinstate no-show", "Ada Lovelace", "Room category", "Reason for reinstatement")
      expect(dialog.at_css("select[name='booking[booking_rooms_attributes][0][room_type_id]']")).to be_present
      expect(dialog.at_css("select[name='booking[booking_rooms_attributes][0][room_number]']")).to be_present
      expect(dialog.at_css("input[name='booking[booking_rooms_attributes][0][id]']")).to be_present
      expect(dialog.at_css("[data-controller='booking-actions--reinstate-editor']")).to be_present
      expect(response.body).not_to include("reinstatements[")
      expect(response.body).not_to include("<!DOCTYPE html>")
      expect(response.body).not_to include("offcanvas")
    end

    it "renders a master-detail radio selector with per-child panels for a group" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      get hotel_booking_action_reinstate_no_show_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet" }

      document = Nokogiri::HTML(response.body)
      dialog = document.at_css("dialog#booking-reinstate-sheet")
      expect(dialog.at_css("input[type='hidden'][name='target_scope'][value='individual']")).to be_present
      expect(dialog.at_css("select[name='reinstatements[#{booking.id}][booking_rooms_attributes][0][room_type_id]']")).to be_present
      expect(dialog.css("section[data-group-lifecycle-targets-target='panel']").size).to eq(2)
    end

    it "renders into the secondary frame when launched stacked" do
      get hotel_booking_action_reinstate_no_show_path(hotel, booking),
        headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

      document = Nokogiri::HTML(response.body)
      expect(document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-reinstate-sheet")).to be_present
    end
  end

  describe "POST the reinstate" do
    it "reinstates the booking and completes the sheet on a Turbo submission" do
      room = booking.booking_rooms.first
      stub_reinstate_reservation(success: true)

      post hotel_booking_action_reinstate_no_show_path(hotel, booking),
        params: { retroactive_reason: "Guest arrived late", booking: { booking_rooms_attributes: { "0" => { id: room.id, room_type_id: room.room_type_id, room_number: "101" } } } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="booking_action_sheet"')
      expect(Bookings::ReinstateReservation).to have_received(:new).with(
        hash_including(booking: booking, user: user, options: hash_including(reason: "Guest arrived late", override_night_audit: true))
      )
    end

    it "redirects to the control panel on a direct request" do
      stub_reinstate_reservation(success: true)

      post hotel_booking_action_reinstate_no_show_path(hotel, booking),
        params: { retroactive_reason: "Guest arrived late", booking: { booking_rooms_attributes: { "0" => { room_type_id: room_type.id, room_number: "101" } } } }

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))
      expect(flash[:notice]).to eq("Booking reinstated and checked in successfully.")
    end

    it "keeps the sheet open with an error when the reason is blank" do
      allow(Bookings::ReinstateReservation).to receive(:new)

      post hotel_booking_action_reinstate_no_show_path(hotel, booking),
        params: { retroactive_reason: "", booking: { booking_rooms_attributes: { "0" => { room_type_id: room_type.id, room_number: "101" } } } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("dialog", "Reason for reinstatement is required.")
      expect(Bookings::ReinstateReservation).not_to have_received(:new)
    end

    it "keeps the sheet open with the service error when reinstatement fails" do
      stub_reinstate_reservation(success: false, error: "Selected room is no longer available.")

      post hotel_booking_action_reinstate_no_show_path(hotel, booking),
        params: { retroactive_reason: "Guest arrived late", booking: { booking_rooms_attributes: { "0" => { room_type_id: room_type.id, room_number: "101" } } } },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Failed to reinstate booking: Selected room is no longer available.")
    end

    it "submits child-specific attributes to the group batch service" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      room = booking.booking_rooms.first
      allow(Bookings::ReinstateGroup).to receive(:call).and_return(OpenStruct.new(success?: true, bookings: [ booking ]))

      post hotel_booking_action_reinstate_no_show_path(hotel, booking),
        params: {
          target_scope: "individual",
          booking_ids: [ booking.id ],
          retroactive_reason: "Guest arrived late",
          reinstatements: { booking.id.to_s => { booking_rooms_attributes: { "0" => { id: room.id, room_type_id: room.room_type_id, room_number: "101", rate_plan_id: "" } } } }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(Bookings::ReinstateGroup).to have_received(:call).with(
        group_booking: group,
        booking_attributes: hash_including(booking.id.to_s),
        user: user,
        options: hash_including(reason: "Guest arrived late", override_night_audit: true)
      )
    end

    it "closes with an alert when a selected group child is not configured" do
      group = create(:group_booking, hotel: hotel, name: "Conference Group")
      booking.update!(group_booking: group, group_position: 1)
      first_room = booking.booking_rooms.first
      second = create_group_child(group, position: 2, room_number: "102", guest_name: "Grace Hopper")

      post hotel_booking_action_reinstate_no_show_path(hotel, booking),
        params: {
          target_scope: "individual",
          booking_ids: [ booking.id, second.id ],
          retroactive_reason: "Guest arrived late",
          reinstatements: { booking.id.to_s => { booking_rooms_attributes: { "0" => { id: first_room.id, room_type_id: first_room.room_type_id, room_number: "101" } } } }
        },
        headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('action="complete_sheet"')
      expect(flash[:alert]).to include("Every selected booking must be configured")
    end

    it "blocks reinstate without manage_bookings permission" do
      role.role_permissions.destroy_all

      post hotel_booking_action_reinstate_no_show_path(hotel, booking),
        params: { retroactive_reason: "Guest arrived late" }

      expect(response).to have_http_status(:redirect)
      expect(booking.reload.status).to eq("no_show")
    end

    it "does not find a booking from another hotel" do
      other_booking = create(:booking, hotel: other_hotel, status: "no_show")

      post hotel_booking_action_reinstate_no_show_path(hotel, other_booking),
        params: { retroactive_reason: "Guest arrived late" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
