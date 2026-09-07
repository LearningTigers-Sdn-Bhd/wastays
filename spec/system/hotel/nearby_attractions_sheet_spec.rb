# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nearby attractions sheet", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel_maps_url) { "https://www.google.com/maps/place/Test+Hotel/@5.9800,116.0700,15z" }
  let(:hotel) { create(:hotel, account: account, status: "live", google_map_link: hotel_maps_url) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:attraction_maps_url) { "https://www.google.com/maps/place/Batu+Caves/@5.9850,116.0750,15z" }

  before do
    driven_by(:cuprite)

    manage_profile = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |permission|
      permission.name = "Manage Hotel Profile"
    end
    RolePermission.find_or_create_by!(role: role, permission: manage_profile)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "previews, adds, and edits an attraction without leaving the index" do
    visit hotel_nearby_attractions_path(hotel)

    expect(page).to have_no_css("dialog#nearby-attraction-sheet")
    click_link "Add attraction", match: :first

    expect(page).to have_css("dialog#nearby-attraction-sheet[open]")
    expect(page).to have_current_path(hotel_nearby_attractions_path(hotel))
    expect(page).to have_content("Add Nearby Attraction")

    within("dialog#nearby-attraction-sheet") do
      fill_in "Google Maps URL", with: "https://maps.app.goo.gl/example"
      click_in_overlay "Find attraction"
    end

    expect(page).to have_css("dialog#nearby-attraction-sheet[open]")
    expect(page).to have_content("Enter a full Google Maps browser URL.")

    within("dialog#nearby-attraction-sheet") do
      fill_in "Google Maps URL", with: attraction_maps_url
      click_in_overlay "Find attraction"
    end

    expect(page).to have_content("Review Nearby Attraction")
    expect(page).to have_content("Batu Caves")
    expect(page).to have_content("straight-line distance from your hotel")

    within("dialog#nearby-attraction-sheet") { click_in_overlay "Create and add" }

    expect(page).to have_no_css("dialog#nearby-attraction-sheet[open]")
    expect(page).to have_current_path(hotel_nearby_attractions_path(hotel))
    within("#nearby_attractions_list") do
      expect(page).to have_content("Batu Caves")
      expect(page).to have_no_content("Pending")
      expect(page).to have_no_content("Approved")
    end

    within("#nearby_attractions_list") do
      find("button[aria-label='Actions for Batu Caves']", match: :first).click
      click_link "Edit guest description", match: :first
    end

    expect(page).to have_css("dialog#nearby-attraction-sheet[open]")
    within("dialog#nearby-attraction-sheet") do
      fill_in "Guest description", with: "Visit in the morning for cooler weather."
      click_in_overlay "Save description"
    end

    expect(page).to have_content("Guest description updated.")
    expect(page).to have_no_css("dialog#nearby-attraction-sheet[open]")
    within("#nearby_attractions_list") do
      expect(page).to have_content("Visit in the morning for cooler weather.")
    end
  end
end
