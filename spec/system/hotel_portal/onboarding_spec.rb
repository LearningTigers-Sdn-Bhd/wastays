# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel onboarding shell", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as_system(user)
  end

  it "offers compact progress details on a narrow screen" do
    page.current_window.resize_to(390, 844)

    visit hotel_onboarding_path(hotel)

    expect(page).to have_css("details summary", text: "Property · Phase 1 of 6")
    find("details summary").click
    expect(page).to have_css("details[open]", text: "Rooms & rates")
    expect(page).to have_css("details[open]", text: "Locked")
  end

  it "resumes setup and advances through an available step" do
    visit hotel_onboarding_path(hotel)

    expect(page).to have_css("h1", text: "Property profile")
    expect(page).to have_css("nav[aria-label='Onboarding progress']")
    expect(page).to have_button("Save & continue")

    click_button "Save & continue"

    expect(page).to have_current_path(hotel_onboarding_section_path(hotel, section_key: "roles_permissions"))
    expect(page).to have_css("h1", text: "Roles and permissions")
    expect(page).to have_link("Back", href: hotel_onboarding_section_path(hotel, section_key: "property_profile"))
  end
end
