# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin attraction registry", type: :system do
  let(:superadmin) { create(:user, :superadmin) }
  let(:google_maps_url) do
    "https://www.google.com/maps/place/Signal+Hill+Observatory/@5.99020,116.07550,15z"
  end

  before do
    driven_by(:cuprite)
    sign_in_as_system(superadmin)
  end

  it "previews and creates an approved attraction from a Google Maps URL" do
    visit admin_attractions_path

    click_link "Add attraction"
    expect(page).to have_css("dialog#add-attraction-sheet[open]")

    fill_in "Google Maps URL", with: google_maps_url
    click_button "Find attraction"

    expect(page).to have_content("Detected attraction")
    expect(page).to have_content("Signal Hill Observatory")

    click_button "Create and approve"

    expect(page).to have_current_path(admin_attractions_path, ignore_query: true)
    expect(page).to have_content("Attraction approved and added to the registry.")
    expect(page).to have_content("Signal Hill Observatory")
    expect(Attraction.find_by(name: "Signal Hill Observatory")).to be_status_approved
  end
end
