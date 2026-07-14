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

  it "loads direct tab links and updates the URL and breadcrumb" do
    visit hotel_notification_settings_path(hotel)

    expect(page).to have_current_path(hotel_notification_settings_path(hotel))
    expect(page).to have_css("h2", text: "Communication & Notifications")
    expect(page).to have_no_css("h2", text: "AI Concierge Configuration")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Notifications")

    within("[data-controller='breadcrumb-dropdown']") do
      expect(page).to have_text("General")
      expect(page).to have_text("Notifications")
    end
    within("[data-testid='settings-tabs']") do
      expect(page).to have_link("Notifications", href: hotel_notification_settings_path(hotel))
      expect(all("a").map { |link| link.text.squish }).to eq([ "General Settings", "Rate Settings", "Notifications", "Plan & Billing" ])
    end

    visit hotel_ai_concierge_settings_path(hotel)

    expect(page).to have_current_path(hotel_ai_concierge_settings_path(hotel))
    expect(page).to have_css("h2", text: "AI Concierge Configuration")
    expect(page).to have_no_css("h2", text: "Communication & Notifications")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "AI Concierge")
    expect(page).to have_css("[data-controller='breadcrumb-dropdown']", text: "Guest Content")
    within("[data-testid='settings-tabs']") { expect(page).to have_no_link("Notifications") }
  end

  it "falls back to General for an unknown tab parameter" do
    visit hotel_settings_path(hotel, tab: "unknown")

    expect(page).to have_current_path(hotel_general_settings_path(hotel))
    expect(page).to have_css("h2", text: "Hotel Settings", visible: :all)
    expect(page).to have_no_css("h2", text: "Banking Details")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "General")
  end

  it "does not expose Banking without manage account permission" do
    RolePermission.find_by!(role: role, permission: manage_account_permission).destroy!

    visit hotel_banking_details_settings_path(hotel)

    expect(page).to have_current_path(hotel_general_settings_path(hotel))
    expect(page).to have_no_link("Banking Details", href: hotel_banking_details_settings_path(hotel))
    expect(page).to have_no_css("h2", text: "Banking Details")
    expect(page).to have_css("h2", text: "Hotel Settings", visible: :all)
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "General")
  end

  it "shows only Banking to an account-only user" do
    RolePermission.find_by!(role: role, permission: manage_profile_permission).destroy!

    visit hotel_general_settings_path(hotel)

    expect(page).to have_current_path(hotel_banking_details_settings_path(hotel))
    expect(page).to have_link("Banking Details", href: hotel_banking_details_settings_path(hotel))
    expect(page).to have_no_link("General Settings", href: hotel_general_settings_path(hotel))
    expect(page).to have_no_css("h2", text: "Hotel Settings", visible: :all)
    expect(page).to have_css("h2", text: "Banking Details")
    expect(page).to have_css("[data-tabs-breadcrumb-label]", text: "Banking")
  end
end
