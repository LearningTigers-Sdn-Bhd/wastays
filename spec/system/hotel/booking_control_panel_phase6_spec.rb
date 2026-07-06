# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking control panel Phase 6", type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "hotel_staff", email: "phase6@example.com") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:booking) { create(:booking, hotel: hotel) }

  before do |example|
    driven_by(example.metadata[:js] ? :cuprite : :rack_test)
    %w[view_bookings manage_bookings].each do |slug|
      role.permissions << Permission.find_or_create_by!(slug: slug) { |record| record.name = slug.humanize }
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:booking_room, booking: booking)
    guest = create(:guest, email: "hanami@mail.com", phone: "+60123451234", government_id: "P4821")
    create(:booking_guest, booking: booking, guest: guest, is_primary: true)
    folio = create(:booking_folio, booking: booking, hotel: hotel, is_primary: true)
    create(:deposit, booking: booking, hotel: hotel, booking_folio: folio, amount: 175, status: "held")
    create(:housekeeping_request, booking: booking, request_details: "Fresh towels", status: "pending")
    create(:complaint_request, booking: booking, complaint_details: "Noisy hallway", status: "pending")

    visit login_path
    fill_in "Email Address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In to Portal"
  end

  it "uses contextual rails while navigating the core Phase 6 tabs" do
    visit hotel_booking_control_panel_path(hotel, booking, tab: "room_and_rate")
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Room & Rate")

    click_link "Guest Details"
    expect(page).to have_current_path(hotel_booking_control_panel_path(hotel, booking, tab: "guest_details"))
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Primary guest for this room")
    expect(page).to have_content("h***@mail.com")
    expect(page).to have_content("Guest Profile")

    click_link "Security Deposits"
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Security Deposits")
    expect(page).to have_content("MYR 175.00")

    click_link "Billing Preferences"
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Billing parties")

    click_link "Folio Operations"
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Ledger")
    expect(page).not_to have_content("Manage Folio Windows")

    click_link "Requests"
    expect(page).to have_css('[data-layout-mode="left_and_center"]')
    expect(page).to have_content("Fresh towels")
    expect(page).to have_content("Noisy hallway")
  end

  it "clicks Apply changes in the billing routes offcanvas", js: true do
    role.permissions << Permission.find_or_create_by!(slug: "manage_folio_movements") { |record| record.name = "Manage Folio Movements" }
    Financials::EnsureDefaultTransactionCodes.call(hotel)
    parent_code = create(:transaction_code, hotel: hotel, kind: "charge", code: "SPA", name: "Spa charge")

    visit hotel_booking_control_panel_path(hotel, booking, tab: "billing_preferences")
    click_link "Change Billing Routes"

    expect(page).to have_css("#offcanvas_drawer_container.block", visible: :all)
    within("#offcanvas_drawer") do
      expect(page).to have_content(/change billing routes/i)
      expect(page).to have_content(parent_code.code)
      click_button "Apply changes"
    end
    expect(page).to have_css("#offcanvas_drawer_container.hidden", visible: :all, wait: 3)
  end
end
