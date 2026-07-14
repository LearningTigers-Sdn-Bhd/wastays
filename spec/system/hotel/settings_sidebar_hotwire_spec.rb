# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel settings sidebar Hotwire navigation", type: :system, js: true do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    driven_by(:cuprite)

    %w[view_bookings manage_hotel_profile manage_account manage_users manage_general_ledger_maps view_audit_logs].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.tr("_", " ").titleize, slug: slug)
      create(:role_permission, role: role, permission: permission)
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    plan = create(:plan)
    feature_group = create(:feature_group)
    hotel.update!(plan: plan)
    %w[ai_concierge_page role_based_access_control full_audit_trail].each do |slug|
      create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: slug), enabled: true)
    end

    sign_in_through_ui(user)
  end

  it "switches sidebar menus on Turbo visits into and out of settings" do
    visit hotel_dashboard_path(hotel)

    find("#hotel-profile-toggle").click
    click_link "Settings", href: hotel_general_settings_path(hotel)

    expect(page).to have_current_path(hotel_general_settings_path(hotel))
    within("#hotel-sidebar") do
      within(".sidebar-header-container") do
        expect(page).to have_link("Back to previous page", href: hotel_dashboard_path(hotel))
      end
      within(".sidebar-footer") do
        expect(page).to have_no_link("Back to previous page")
        expect(page).to have_link("Help & support")
      end
      expect(page).to have_link("General", href: hotel_general_settings_path(hotel))
      expect(page).to have_no_link("Dashboard", href: hotel_dashboard_path(hotel))
      expect(page).to have_no_link("Settings")
      expect(page).to have_no_link("Homepage")
    end

    within("#hotel-sidebar") { click_link "Back to previous page" }

    expect(page).to have_current_path(hotel_dashboard_path(hotel))
    within("#hotel-sidebar") do
      expect(page).to have_link("Dashboard", href: hotel_dashboard_path(hotel))
      expect(page).to have_no_link("Back to previous page")
      expect(page).to have_no_link("Settings")
      expect(page).to have_no_link("Homepage")
      expect(page).to have_link("Help & support")
    end

    profile_toggle = find("#hotel-profile-toggle[aria-label='Open profile menu'][aria-haspopup='menu'][aria-expanded='false']")
    profile_toggle.send_keys(:down)
    expect(page).to have_css("#hotel-profile-toggle[aria-expanded='true']")
    expect(page).to have_css("#hotel-profile-menu-actions[role='menu']")
    expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq("My account")
    page.execute_script("document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }))")
    expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq("Settings")
    expect(page).to have_css("a[role='menuitem'][href='#{hotel_general_settings_path(hotel)}']", text: "Settings")
    page.execute_script("document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))")
    expect(page).to have_css("#hotel-profile-menu.hidden", visible: :all)
    expect(page).to have_css("#hotel-profile-toggle[aria-expanded='false']:focus")
  end

  it "shows grouped settings hub navigation" do
    visit hotel_general_settings_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_link("Back to previous page")
      expect(page).to have_link("General", href: hotel_general_settings_path(hotel))
      expect(page).to have_link("Property", href: edit_hotel_profile_path(hotel))
      expect(page).to have_link("Finance", href: hotel_banking_details_settings_path(hotel))
      expect(page).to have_link("Guest Content", href: hotel_ai_concierge_settings_path(hotel))
      expect(page).to have_link("Team", href: hotel_users_path(hotel))

      expect(page).to have_no_link("Room Categories")
      expect(page).to have_no_link("Transaction Codes")
      expect(page).to have_no_link("Staff Management")
      expect(page).to have_no_link("Plan & Billing")
    end

    # Group tabs should be visible on the page
    within("[data-testid='settings-tabs']") do
      expect(page).to have_link("General Settings", href: hotel_general_settings_path(hotel))
      expect(page).to have_link("Plan & Billing", href: hotel_plan_path(hotel))
    end
  end

  it "keeps settings sidebar when visiting a hub destination" do
    visit hotel_room_types_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_link("Back to previous page")
      expect(page).to have_no_link("Homepage")
      expect(page).to have_link("Help & support")
    end
  end

  it "keeps each settings group active after selecting a secondary tab" do
    [
      [ hotel_general_settings_path(hotel), "Notifications", hotel_notification_settings_path(hotel), "General" ],
      [ edit_hotel_profile_path(hotel), "Room Categories", hotel_room_types_path(hotel), "Property" ],
      [ hotel_taxes_fees_path(hotel), "Transaction Codes", hotel_transaction_codes_path(hotel), "Finance" ],
      [ hotel_ai_concierge_settings_path(hotel), "Policies", hotel_knowledge_policies_path(hotel), "Guest Content" ],
      [ hotel_users_path(hotel), "Roles & Permissions", hotel_roles_path(hotel), "Team" ]
    ].each do |first_tab_path, secondary_tab_label, secondary_tab_path, sidebar_label|
      visit first_tab_path

      within("#hotel-sidebar") do
        expect(page).to have_css("a.sidebar-nav-link-active", text: sidebar_label)
      end

      within("[data-testid='settings-tabs']") { click_link secondary_tab_label }

      expect(page).to have_current_path(secondary_tab_path)
      within("#hotel-sidebar") do
        expect(page).to have_css("a.sidebar-nav-link-active", text: sidebar_label)
      end
    end
  end

  it "keeps the settings header compact after a collapsed Turbo mode switch" do
    visit hotel_dashboard_path(hotel)
    find('button[aria-label="Collapse sidebar"]').click

    find("#hotel-profile-toggle").click
    click_link "Settings", href: hotel_general_settings_path(hotel)

    within("#hotel-sidebar.sidebar-collapsed .sidebar-header-container") do
      back_link = find("a[data-sidebar-tooltip='Back to previous page'][aria-label='Back to previous page']", visible: :all)
      expect(back_link).to have_css(".sidebar-label.hidden", visible: :all)

      back_link.hover
    end
    within("#hotel-sidebar") do
      expect(page).to have_css(".sidebar-tooltip", text: "Back to previous page", visible: :visible)
    end
  end
end
