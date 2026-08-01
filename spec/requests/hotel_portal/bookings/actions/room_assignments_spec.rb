# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions room assignments", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) do
    create(:room_type, hotel:, name: "Garden Suite", quantity: 3, room_number_mode: "custom", room_numbers: %w[101 102 103])
  end
  let(:rate_plan) { create(:rate_plan, room_type:, name: "Flexible Rate") }
  let(:booking) do
    create(
      :booking,
      hotel:,
      guest_name: "Ada Lovelace",
      status: "confirmed",
      check_in: Date.current,
      check_out: Date.current + 2.days
    ).tap do |record|
      create(:booking_room, booking: record, room_type:, rate_plan:, room_number: "101")
    end
  end

  def grant_permission(slug)
    permission = Permission.find_by(slug:) || create(:permission, slug:, name: slug.humanize)
    create(:role_permission, role:, permission:)
  end

  before do
    BusinessDates::ResetAuthority.call!(hotel:, date: Date.current)
    grant_permission("manage_bookings")
    grant_permission("view_bookings")
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  it "renders the Room Sheet with category and room selects, no rate control" do
    get hotel_booking_action_edit_room_path(hotel, booking),
      headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    dialog = document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-room-sheet")
    expect(dialog).to be_present
    expect(dialog.text).to include("Change room", "Room", "Estimated value")
    expect(dialog.at_css("select#booking_room_type_id.panel-select-menu__native")).to be_present
    expect(dialog.at_css("select#booking_room_number.panel-select-menu__native")).to be_present
    expect(dialog.at_css("select#booking_rate_selection")).to be_nil
    expect(response.body).not_to include("offcanvas", "drawer")
  end

  it "reassigns the room and completes the requesting Sheet" do
    patch hotel_booking_action_edit_room_path(hotel, booking), params: {
      return_to: hotel_stay_view_path(hotel),
      booking: { room_type_id: room_type.id, room_number: "102", check_in: booking.check_in, check_out: booking.check_out }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet"', hotel_stay_view_path(hotel))
    expect(booking.booking_rooms.first.reload.room_number).to eq("102")
  end

  it "shifts room and dates together on a move proposal" do
    patch hotel_booking_action_edit_room_path(hotel, booking), params: {
      proposal_kind: "move",
      return_to: hotel_stay_view_path(hotel),
      booking: { room_type_id: room_type.id, room_number: "102", check_in: Date.current + 1.day, check_out: Date.current + 3.days }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(booking.reload.check_in.to_date).to eq(Date.current + 1.day)
    expect(booking.booking_rooms.first.reload.room_number).to eq("102")
  end

  it "surfaces the proposed room and dates banner on a move proposal GET" do
    get hotel_booking_action_edit_room_path(hotel, booking), params: {
      proposal_kind: "move",
      booking: { room_type_id: room_type.id, room_number: "102", check_in: Date.current + 1.day, check_out: Date.current + 3.days }
    }, headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Review the proposed room and dates", "Nothing changes until you save")
    expect(booking.booking_rooms.first.reload.room_number).to eq("101")
  end

  it "blocks ineligible, unauthorized, and cross-hotel access" do
    booking.update_column(:status, "completed")
    get hotel_booking_action_edit_room_path(hotel, booking)
    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))

    role.role_permissions.destroy_all
    get hotel_booking_action_edit_room_path(hotel, booking)
    expect(response).to redirect_to(root_path)

    grant_permission("manage_bookings")
    other_booking = create(:booking, hotel: other_hotel)
    get hotel_booking_action_edit_room_path(hotel, other_booking)
    expect(response).to have_http_status(:not_found)
  end
end
