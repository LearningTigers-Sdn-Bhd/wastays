require "rails_helper"

RSpec.describe "Hotel booking show tab redirects", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role.permissions << (Permission.find_by(slug: "view_bookings") || create(:permission, slug: "view_bookings"))
    role.permissions << (Permission.find_by(slug: "manage_bookings") || create(:permission, slug: "manage_bookings"))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "redirects the legacy 'requests' tab to the Booking Control Panel's housekeeping_requests tab" do
    get hotel_booking_path(hotel, booking, tab: "requests")

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "housekeeping_requests"))
    expect(response).to have_http_status(:moved_permanently)

    follow_redirect!
    expect(response.body).to include('aria-current="page"')
    expect(response.body).to include("Requests")
  end

  it "redirects the legacy 'history' tab to the Booking Control Panel's audit_trails tab" do
    get hotel_booking_path(hotel, booking, tab: "history")

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "audit_trails"))

    follow_redirect!
    expect(response.body).to include("Audit Trails")
  end

  it "falls back to booking details for an unknown tab parameter" do
    get hotel_booking_path(hotel, booking, tab: "unknown")

    expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))

    follow_redirect!
    expect(response.body).to include("Booking Details")
  end
end
