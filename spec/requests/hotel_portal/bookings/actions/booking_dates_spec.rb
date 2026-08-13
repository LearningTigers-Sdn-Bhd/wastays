# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions booking dates", frozen_time: :business_day, type: :request do
  let(:hotel) { create(:hotel, status: "live") }
  let(:other_hotel) { create(:hotel, status: "live") }
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

  it "renders the Dates Sheet in the requesting frame" do
    get hotel_booking_action_edit_dates_path(hotel, booking),
      headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    dialog = document.at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-dates-sheet")
    expect(dialog).to be_present
    expect(dialog.text).to include("Edit dates", "Current stay", "Stay dates", "Estimated value")
    expect(dialog.at_css("#booking_check_in")).to be_present
    expect(dialog.at_css("#booking_check_out")).to be_present
    expect(dialog.at_css("select#booking_room_number")).to be_nil
    expect(dialog.at_css("select#booking_rate_selection")).to be_nil
    expect(response.body).not_to include("offcanvas", "drawer")
  end

  it "updates stay dates and completes the requesting Sheet" do
    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      return_to: hotel_stay_view_path(hotel),
      booking: { check_in: Date.current + 1.day, check_out: Date.current + 4.days }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet"', hotel_stay_view_path(hotel))
    expect(booking.reload.check_in.to_date).to eq(Date.current + 1.day)
    expect(booking.check_out.to_date).to eq(Date.current + 4.days)
    expect(booking.booking_rooms.first.reload.room_number).to eq("101")
  end

  it "shows the proposed-dates banner without mutating on a dates proposal" do
    original = [ booking.check_in, booking.check_out ]

    get hotel_booking_action_edit_dates_path(hotel, booking), params: {
      proposal_kind: "dates",
      booking: { check_in: Date.current + 1.day, check_out: Date.current + 3.days }
    }, headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include("Check the proposed stay dates", "Nothing changes until you save")
    expect([ booking.reload.check_in, booking.check_out ]).to eq(original)
  end

  it "returns 422 with submitted values when a group batch selects no eligible booking" do
    group = create(:group_booking, hotel:)
    booking.update!(group_booking: group, group_position: 1)

    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      target_scope: "group",
      booking_ids: [ "" ],
      booking: { check_in: Date.current + 3.days, check_out: Date.current + 4.days }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("The stay dates could not be updated", (Date.current + 3.days).iso8601)
    expect(booking.reload.check_in.to_date).to eq(Date.current)
  end

  it "updates dates for selected group bookings" do
    group = create(:group_booking, hotel:)
    booking.update!(group_booking: group, group_position: 1)
    sibling = create(:booking, hotel:, group_booking: group, group_position: 2, status: "confirmed", check_in: booking.check_in, check_out: booking.check_out)
    create(:booking_room, booking: sibling, room_type:, rate_plan:, room_number: "102")

    patch hotel_booking_action_edit_dates_path(hotel, booking), params: {
      target_scope: "group",
      booking_ids: [ booking.id, sibling.id ],
      booking: { check_in: Date.current + 2.days, check_out: Date.current + 5.days }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(booking.reload.check_in.to_date).to eq(Date.current + 2.days)
    expect(sibling.reload.check_out.to_date).to eq(Date.current + 5.days)
    expect(booking.booking_rooms.first.reload.room_number).to eq("101")
    expect(sibling.booking_rooms.first.reload.room_number).to eq("102")
  end

  it "blocks ineligible, unauthorized, and cross-hotel access" do
    booking.update_column(:status, "completed")
    get hotel_booking_action_edit_dates_path(hotel, booking)
    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))

    role.role_permissions.destroy_all
    get hotel_booking_action_edit_dates_path(hotel, booking)
    expect(response).to redirect_to(root_path)

    grant_permission("manage_bookings")
    other_booking = create(:booking, hotel: other_hotel)
    get hotel_booking_action_edit_dates_path(hotel, other_booking)
    expect(response).to have_http_status(:not_found)
  end
end
