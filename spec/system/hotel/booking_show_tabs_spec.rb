require "rails_helper"

RSpec.describe "Hotel booking show tabs", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "frontdesk@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    driven_by(:cuprite)

    %w[view_bookings manage_bookings].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  it "loads direct tab links and persists tab switches in the URL" do
    visit hotel_booking_path(hotel, booking, tab: "requests")

    expect(page).to have_current_path(hotel_booking_path(hotel, booking, tab: "requests"))
    expect(page).to have_css("[data-testid='booking-requests-panel']")
    expect(page).to have_css("[data-testid='booking-details-panel']", visible: :hidden)
    expect(page).to have_css("[data-tab-breadcrumb-label]", text: "Requests")

    click_button "History"

    expect(page).to have_current_path(hotel_booking_path(hotel, booking, tab: "history"))
    expect(page).to have_css("[data-testid='booking-history-panel']")
    expect(page).to have_css("[data-testid='booking-requests-panel']", visible: :hidden)
    expect(page).to have_css("[data-tab-breadcrumb-label]", text: "History")
  end

  it "falls back to booking details for an unknown tab parameter" do
    visit hotel_booking_path(hotel, booking, tab: "unknown")

    expect(page).to have_css("[data-testid='booking-details-panel']")
    expect(page).to have_css("[data-testid='booking-requests-panel']", visible: :hidden)
    expect(page).to have_css("[data-testid='booking-history-panel']", visible: :hidden)
    expect(page).to have_css("[data-tab-breadcrumb-label]", text: "Booking Details")
  end
end
