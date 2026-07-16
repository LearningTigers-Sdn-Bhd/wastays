# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nearby attractions sheet", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    driven_by(:cuprite)

    manage_profile = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: manage_profile)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "creates and edits nearby attractions in a right-side sheet without leaving the index" do
    visit hotel_nearby_attractions_path(hotel)

    expect(page).to have_no_css("dialog#nearby-attraction-sheet")

    click_link "Create"

    expect(page).to have_css("dialog#nearby-attraction-sheet[open]")
    expect(page).to have_current_path(hotel_nearby_attractions_path(hotel))
    expect(page).to have_content("Add Nearby Attraction")

    # Submitting invalid keeps the sheet open with the frame re-rendered.
    within("dialog#nearby-attraction-sheet") { click_button "Create Nearby Attraction" }
    expect(page).to have_css("dialog#nearby-attraction-sheet[open]")
    expect(page).to have_current_path(hotel_nearby_attractions_path(hotel))

    within("dialog#nearby-attraction-sheet") do
      fill_in "Attraction Name", with: "Batu Caves"
      fill_in "City", with: "Kuala Lumpur"
      fill_in "Country", with: "Malaysia"
      click_button "Create Nearby Attraction"
    end

    expect(page).to have_no_css("dialog#nearby-attraction-sheet[open]")
    expect(page).to have_current_path(hotel_nearby_attractions_path(hotel))
    within("#nearby_attractions_list") { expect(page).to have_content("Batu Caves") }

    # Re-open a fresh Create sheet (verifies the frame reset after close).
    click_link "Create"
    expect(page).to have_css("dialog#nearby-attraction-sheet[open]")
    within("dialog#nearby-attraction-sheet") { expect(page).to have_field("Attraction Name", with: "") }
    find("dialog#nearby-attraction-sheet").send_keys(:escape)
    expect(page).to have_no_css("dialog#nearby-attraction-sheet[open]")

    # Edit the existing row via its dropdown.
    within("#nearby_attractions_list") do
      find("button[aria-label='Actions for Batu Caves']").click
      click_link "Edit details"
    end

    expect(page).to have_css("dialog#nearby-attraction-sheet[open]")
    within("dialog#nearby-attraction-sheet") do
      expect(page).to have_field("Attraction Name", with: "Batu Caves")
      fill_in "Attraction Name", with: "Batu Caves Temple"
      click_button "Update Nearby Attraction"
    end

    expect(page).to have_no_css("dialog#nearby-attraction-sheet[open]")
    within("#nearby_attractions_list") { expect(page).to have_content("Batu Caves Temple") }
  end
end
