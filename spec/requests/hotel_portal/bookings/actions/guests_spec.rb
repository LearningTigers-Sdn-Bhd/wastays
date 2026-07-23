# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Actions guests", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel:, guest_name: "Primary Guest", status: "confirmed") }

  before do
    permission = Permission.find_by(slug: "manage_bookings") || create(:permission, slug: "manage_bookings", name: "Manage Bookings")
    create(:role_permission, role:, permission:)
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  it "renders the add form in the booking action Sheet" do
    get hotel_booking_action_manage_guest_path(hotel, booking, mode: "add"),
      headers: { "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:success)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("turbo-frame#booking_action_sheet dialog#booking-guest-sheet")).to be_present
    expect(document.at_css("input[name='guest[name]'][autofocus]")).to be_present
    expect(document.css("[data-controller~='panels-ui--combobox']").size).to eq(1)
    expect(document.css("[data-controller~='panels-ui--select-menu']").size).to eq(2)
    expect(document.at_css("[data-controller~='panels-ui--date-picker'] input[name='guest[date_of_birth]']")).to be_present
    country_options = document.css("select[name='guest[country]'] option").map { |option| [ option.text, option["value"] ] }
    expect(country_options).to include([ "Malaysia", "Malaysia" ], [ "Singapore", "Singapore" ])
    expect(document.at_css("input[name='guest[date_of_birth]'][type='date']")).to be_nil
    expect(response.body).not_to include("offcanvas")
  end

  it "adds a guest and completes the requesting Sheet" do
    post hotel_booking_action_manage_guest_path(hotel, booking, mode: "add"),
      params: { guest: { name: "Added Guest", country: "Malaysia", document_type: "passport", date_of_birth: "1993-04-05" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('action="complete_sheet"', 'target="booking_action_sheet_secondary"')
    expect(booking.booking_guests.find_by!(is_primary: false).guest.name).to eq("Added Guest")
  end

  it "keeps the Sheet open when guest validation fails" do
    post hotel_booking_action_manage_guest_path(hotel, booking, mode: "add"),
      params: { guest: { name: "", country: "Malaysia" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("booking-guest-sheet", "Guest could not be saved", "Name can&#39;t be blank")
  end

  it "updates an inline guest snapshot and redirects to the selected workspace" do
    booking_guest = create(:booking_guest, booking:, is_primary: false)
    original_name = booking_guest.guest.name
    return_to = hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: booking_guest.id)

    patch hotel_booking_action_manage_guest_path(hotel, booking, mode: "edit_additional", booking_guest_id: booking_guest.id), params: {
      return_to:,
      guest: {
        name: "Stay Snapshot", email: "stay@example.com", country: "Malaysia",
        document_type: "passport", date_of_birth: "1990-01-01"
      }
    }

    expect(response).to redirect_to(return_to)
    expect(booking_guest.reload.name_snapshot).to eq("Stay Snapshot")
    expect(booking_guest.guest.reload.name).to eq(original_name)
  end

  it "renders and completes additional-guest removal" do
    booking_guest = create(:booking_guest, booking:, is_primary: false)

    get hotel_booking_action_remove_guest_path(hotel, booking, booking_guest),
      headers: { "Turbo-Frame" => "booking_action_sheet_secondary" }
    expect(Nokogiri::HTML(response.body).at_css("turbo-frame#booking_action_sheet_secondary dialog#booking-guest-removal-sheet")).to be_present

    delete hotel_booking_action_remove_guest_path(hotel, booking, booking_guest),
      headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "booking_action_sheet_secondary" }
    expect(response.body).to include('target="booking_action_sheet_secondary"')
    expect(booking.booking_guests.where(id: booking_guest.id)).not_to exist
  end

  it "rejects removal of the primary guest" do
    booking_guest = create(:booking_guest, booking:, is_primary: true)

    get hotel_booking_action_remove_guest_path(hotel, booking, booking_guest)

    expect(response).to have_http_status(:not_found)
  end

  it "makes an additional guest primary" do
    original = create(:booking_guest, booking:, is_primary: true)
    replacement = create(:booking_guest, booking:, is_primary: false)

    patch hotel_booking_action_set_primary_guest_path(hotel, booking, replacement)

    expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "guest_details", booking_guest_id: replacement.id))
    expect(replacement.reload).to be_primary
    expect(original.reload).not_to be_primary
  end

  it "requires manage-bookings permission" do
    role.role_permissions.destroy_all

    get hotel_booking_action_manage_guest_path(hotel, booking, mode: "add")

    expect(response).to redirect_to(root_path)
  end

  it "rejects unsupported modes and guests from another booking" do
    other_guest = create(:booking_guest, is_primary: false)

    get hotel_booking_action_manage_guest_path(hotel, booking, mode: "unsupported")
    expect(response).to have_http_status(:not_found)

    get hotel_booking_action_remove_guest_path(hotel, booking, other_guest)
    expect(response).to have_http_status(:not_found)
  end
end
