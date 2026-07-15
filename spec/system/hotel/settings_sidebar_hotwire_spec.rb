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
    page.execute_script(<<~JS)
      window.sidebarModeErrors = []
      window.addEventListener("error", (event) => window.sidebarModeErrors.push(event.message))
    JS

    open_settings_from_profile

    expect(page).to have_current_path(hotel_general_settings_path(hotel))
    expect(page).to have_no_css("#hotel-sidebar", visible: :all)
    within("#hotel-settings-sidebar") do
      within(".panel-sidebar__header") do
        expect(page).to have_css("a[aria-label='Hotel: #{hotel.name}'][href='#{hotel_dashboard_path(hotel)}']")
      end
      within(".panel-sidebar__footer") do
        expect(page).to have_no_link("Back to previous page")
        expect(page).to have_link("Help & support")
      end
      expect(page).to have_link("General", href: hotel_general_settings_path(hotel))
      expect(page).to have_no_link("Dashboard", href: hotel_dashboard_path(hotel))
      expect(page).to have_no_link("Settings")
      expect(page).to have_no_link("Homepage")
    end

    return_to_dashboard

    expect(page).to have_current_path(hotel_dashboard_path(hotel))
    expect(page).to have_no_css("#hotel-settings-sidebar", visible: :all)
    within("#hotel-sidebar") do
      expect(page).to have_link("Dashboard", href: hotel_dashboard_path(hotel))
      expect(page).to have_no_link("Back to previous page")
      expect(page).to have_no_link("Settings")
      expect(page).to have_no_link("Homepage")
      expect(page).to have_link("Help & support")
    end
    expect(page.evaluate_script("window.sidebarModeErrors")).to be_empty
  end

  it "reconnects profile-menu keyboard navigation after a settings Turbo round trip" do
    visit hotel_dashboard_path(hotel)
    open_settings_from_profile
    expect(page).to have_current_path(hotel_general_settings_path(hotel))

    return_to_dashboard
    expect(page).to have_current_path(hotel_dashboard_path(hotel))
    expect(page).to have_css("#hotel-sidebar")
    expect(page).to have_no_css("#hotel-settings-sidebar", visible: :all)
    wait_for_stimulus_controller("#hotel-profile", "panels-ui--dropdown-menu")

    find("#hotel-profile-trigger[aria-label='Open account menu'][aria-haspopup='menu'][aria-expanded='false']").click
    expect(page).to have_css("#hotel-profile-trigger[aria-expanded='true']")
    expect(page).to have_css("#hotel-profile-menu[role='menu']:popover-open")
    expect(page).to have_css("#hotel-profile-menu a:focus")
    dispatch_key("Home")
    expect(page).to have_css("#hotel-profile-menu a:focus", text: "My account")
    dispatch_key("ArrowDown")
    expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq("Settings")
    expect(page).to have_css("a[role='menuitem'][href='#{hotel_general_settings_path(hotel)}']", text: "Settings")
    dispatch_key("Escape")
    expect(page).to have_no_css("#hotel-profile-menu:popover-open")
    expect(page).to have_css("#hotel-profile-trigger[aria-expanded='false']:focus")
  end

  it "shows grouped settings hub navigation" do
    visit hotel_general_settings_path(hotel)

    within("#hotel-settings-sidebar") do
      expect(page).to have_no_link("Back to previous page")
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
      expect(page).to have_link("General", href: hotel_general_settings_path(hotel))
      expect(page).to have_link("Plan & Billing", href: hotel_plan_path(hotel))
    end
  end

  it "aligns the settings header with the breadcrumb and fills the header menu width" do
    visit hotel_general_settings_path(hotel)

    measurements = page.evaluate_script(<<~JS)
      (() => {
        const sidebar = document.querySelector("#hotel-settings-sidebar")
        const header = sidebar.querySelector(".panel-sidebar__header")
        const headerLink = header.querySelector(".panel-sidebar__link")
        const activeLink = sidebar.querySelector(".panel-sidebar__link[aria-current='page']")
        const breadcrumb = document.querySelector(".portal-breadcrumb-bar")

        return {
          headerLinkWidth: headerLink.getBoundingClientRect().width,
          activeLinkWidth: activeLink.getBoundingClientRect().width,
          headerHeight: header.getBoundingClientRect().height,
          breadcrumbHeight: breadcrumb.getBoundingClientRect().height
        }
      })()
    JS

    expect((measurements["headerHeight"] - measurements["breadcrumbHeight"]).abs).to be <= 1
    expect((measurements["headerLinkWidth"] - measurements["activeLinkWidth"]).abs).to be <= 1
  end

  it "keeps settings sidebar when visiting a hub destination" do
    visit hotel_room_types_path(hotel)

    within("#hotel-settings-sidebar") do
      expect(page).to have_no_link("Back to previous page")
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

      within("#hotel-settings-sidebar") do
        expect(page).to have_css("a.panel-sidebar__link[aria-current='page']", text: sidebar_label)
      end

      within("[data-testid='settings-tabs']") { click_link secondary_tab_label }

      expect(page).to have_current_path(secondary_tab_path)
      within("#hotel-settings-sidebar") do
        expect(page).to have_css("a.panel-sidebar__link[aria-current='page']", text: sidebar_label)
      end
    end
  end

  it "carries the hotel collapse state across layout boundaries" do
    visit hotel_dashboard_path(hotel)
    find('button[aria-label="Collapse navigation"]').click

    open_settings_from_profile

    expect(page).to have_no_css("#hotel-sidebar", visible: :all)
    expect(page).to have_css("#hotel-settings-sidebar[data-collapsed='true']")
    expect(page).to have_no_link("Back to previous page")
  end

  it "persists settings changes to the shared hotel collapse state" do
    visit hotel_general_settings_path(hotel)
    page.execute_script("window.localStorage.removeItem('wastays:hotel-sidebar-collapsed')")

    find('button[aria-label="Collapse navigation"]').click
    expect(page).to have_css("#hotel-settings-sidebar[data-collapsed='true']")

    visit hotel_notification_settings_path(hotel)
    expect(page).to have_css("#hotel-settings-sidebar[data-collapsed='true']")

    within("#hotel-settings-sidebar .panel-sidebar__header") do
      find("a[aria-label='Hotel: #{hotel.name}'][href='#{hotel_dashboard_path(hotel)}']", visible: :all).click
    end
    expect(page).to have_css("#hotel-sidebar[data-collapsed='true']")

    find('button[aria-label="Collapse navigation"]').click
    expect(page).to have_css("#hotel-sidebar[data-collapsed='false']")
  end

  def open_settings_from_profile
    wait_for_stimulus_controller("#hotel-profile", "panels-ui--dropdown-menu")
    find("#hotel-profile-trigger").click
    within("#hotel-profile-menu") { click_link "Settings", href: hotel_general_settings_path(hotel) }
  end

  def return_to_dashboard
    within("#hotel-settings-sidebar .panel-sidebar__header") do
      find("a[aria-label='Hotel: #{hotel.name}'][href='#{hotel_dashboard_path(hotel)}']").click
    end
  end
end
