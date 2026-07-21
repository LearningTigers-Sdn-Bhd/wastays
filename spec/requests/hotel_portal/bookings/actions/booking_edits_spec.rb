# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions booking edits", type: :request do
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

  it "renders the Edit-booking Sheet with details fields and stay-editing links" do
    get hotel_booking_action_edit_booking_path(hotel, booking),
      headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    dialog = document.at_css("dialog#booking-edit-sheet")
    expect(dialog).to be_present
    expect(dialog.at_css("#booking_guest_name")).to be_present
    expect(dialog.at_css("#booking_guarantee_method")).to be_present

    stay_links = dialog.css("a").each_with_object({}) do |anchor, memo|
      memo[anchor.text.squish] = URI.parse(anchor["href"]).path if anchor["data-turbo-frame"] == "booking_action_sheet_secondary"
    end
    expect(stay_links["Edit dates"]).to eq(hotel_booking_action_edit_dates_path(hotel, booking))
    expect(stay_links["Change room"]).to eq(hotel_booking_action_edit_room_path(hotel, booking))
    expect(stay_links["Change rate"]).to eq(hotel_booking_action_edit_rate_path(hotel, booking))
    expect(response.body).not_to include("offcanvas", "drawer")
  end

  it "updates guest and booking details and completes the requesting Sheet" do
    patch hotel_booking_action_edit_booking_path(hotel, booking), params: {
      return_to: hotel_booking_control_panel_path(hotel, booking),
      booking: { guest_name: "Grace Hopper", guest_email: "grace@example.com", source: "phone" }
    }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet"')
    expect(booking.reload.guest_name).to eq("Grace Hopper")
    expect(booking.guest_email).to eq("grace@example.com")
    expect(booking.source).to eq("phone")
  end

  it "blocks unauthorized and cross-hotel access" do
    role.role_permissions.destroy_all
    get hotel_booking_action_edit_booking_path(hotel, booking)
    expect(response).to redirect_to(root_path)

    grant_permission("manage_bookings")
    other_booking = create(:booking, hotel: other_hotel)
    get hotel_booking_action_edit_booking_path(hotel, other_booking)
    expect(response).to have_http_status(:not_found)
  end
end
