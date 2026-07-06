require "rails_helper"

RSpec.describe "Hotel settings tabs", type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "registered") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let!(:manage_account_permission) do
    Permission.find_or_create_by!(slug: "manage_account") { |permission| permission.name = "Manage Account" }
  end
  let!(:manage_profile_permission) do
    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
  end

  before do
    driven_by(:cuprite)

    RolePermission.find_or_create_by!(role: role, permission: manage_account_permission)
    RolePermission.find_or_create_by!(role: role, permission: manage_profile_permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "loads direct tab links and synchronizes tab switches with the URL and breadcrumb" do
    visit hotel_settings_path(hotel, tab: "notifications")

    expect(page).to have_current_path(hotel_settings_path(hotel, tab: "notifications"))
    expect(page).to have_css("[data-testid='settings-notifications-panel']")
    expect(page).to have_css("[data-testid='settings-general-panel']", visible: :hidden)
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Notifications")

    click_button "AI Concierge"

    expect(page).to have_current_path(hotel_settings_path(hotel, tab: "ai"))
    expect(page).to have_css("[data-testid='settings-ai-panel']")
    expect(page).to have_css("[data-testid='settings-notifications-panel']", visible: :hidden)
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "AI Concierge")
  end

  it "falls back to General for an unknown tab parameter" do
    visit hotel_settings_path(hotel, tab: "unknown")

    expect(page).to have_css("[data-testid='settings-general-panel']")
    expect(page).to have_no_css("[data-testid='settings-tax-panel']", visible: :all)
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "General")
  end

  it "does not expose Banking without manage account permission" do
    RolePermission.find_by!(role: role, permission: manage_account_permission).destroy!

    visit hotel_settings_path(hotel, tab: "banking")

    expect(page).to have_no_button("Banking")
    expect(page).to have_no_css("[data-testid='settings-banking-panel']", visible: :all)
    expect(page).to have_css("[data-testid='settings-general-panel']")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "General")
  end

  it "shows only Banking to an account-only user" do
    RolePermission.find_by!(role: role, permission: manage_profile_permission).destroy!

    visit hotel_settings_path(hotel, tab: "general")

    expect(page).to have_button("Banking")
    expect(page).to have_no_button("General")
    expect(page).to have_no_css("[data-testid='settings-general-panel']", visible: :all)
    expect(page).to have_css("[data-testid='settings-banking-panel']")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Banking")
  end
end
