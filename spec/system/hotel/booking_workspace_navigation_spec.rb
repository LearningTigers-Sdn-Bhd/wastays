# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Booking workspace navigation", :business_day, type: :system do
  include_context "booking workspace system setup"

  it "uses standard and entity layouts while navigating the workspace" do
    folio = booking.booking_folios.find_by!(is_primary: true)
    create(:deposit, booking: booking, hotel: hotel, booking_folio: folio, amount: 175, status: "held")
    create(:housekeeping_request, booking: booking, request_details: "Fresh towels", status: "pending")
    create(:complaint_request, booking: booking, complaint_details: "Noisy hallway", status: "pending")

    visit hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")
    expect(page).to have_css('[data-layout-mode="standard"]')
    expect(page).to have_content("Room & Rate")

    within("#booking-workspace-tabs") { click_link "Guests" }
    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details"))
    expect(page).to have_css('[data-layout-mode="entity"]')
    expect(page).to have_content("Primary guest")
    expect(page).to have_field("Email", with: "hanami@mail.com")
    expect(page).to have_content("Guest details recorded for this stay.")
    expect(page).to have_button("Save Guest")

    within("#booking-workspace-tabs") { click_link "Deposits" }
    expect(page).to have_css('[data-layout-mode="standard"]')
    expect(page).to have_content("Deposits")
    expect(page).to have_content("MYR 175.00")

    within("#booking-workspace-tabs") { click_link "Billing" }
    expect(page).to have_css('[data-layout-mode="standard"]')
    expect(page).to have_content("Billing parties")

    within("#booking-workspace-tabs") { click_link "Folios" }
    expect(page).to have_css('[data-layout-mode="entity"]')
    expect(page).to have_content("Ledger")
    expect(page).not_to have_content("Manage Folio Windows")

    within("#booking-workspace-tabs") { click_link "Requests" }
    expect(page).to have_css('[data-layout-mode="standard"]')
    expect(page).to have_content("Fresh towels")
    expect(page).to have_content("Noisy hallway")
  end

  it "re-renders the active tab with Turbo frame navigation", js: true do
    visit hotel_booking_workspace_path(hotel, booking, tab: "room_and_rate")

    within("#booking-workspace-tabs") do
      expect(page).to have_css("a[aria-current='page']", text: "Room & Rate")
      click_link "Guests"
    end

    within("#booking-workspace-tabs") do
      expect(page).to have_css("a[aria-current='page']", text: "Guests")
      expect(page).to have_no_css("a[aria-current='page']", text: "Room & Rate")
    end

    expect(page).to have_current_path(hotel_booking_workspace_path(hotel, booking, tab: "guest_details"))
    expect(page).to have_content("Primary guest")
    expect(page).to have_css("#hotel-breadcrumb", text: "Booking Workspace")
    expect(page).to have_no_css("#hotel-breadcrumb [data-tabs-breadcrumb-label]")
  end
end
