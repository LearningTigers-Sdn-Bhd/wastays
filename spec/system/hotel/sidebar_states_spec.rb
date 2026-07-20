# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel sidebar navigation states", type: :system do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    driven_by(:rack_test)
    %w[room_status_board unified_guest_profile task_assignment_minibar_log no_show_auto_handling].each do |slug|
      create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: slug), enabled: true)
    end

    %w[
      view_reports
      view_bookings
      manage_hotel_profile
      manage_users
      view_payouts
      manage_night_audit
      manage_account
      manage_guest_arrival
      view_room_readiness
      view_guest_records
      manage_requests
      view_reservation_board
      view_audit_logs
    ].each do |slug|
      permission = Permission.find_by(slug: slug) ||
        create(:permission, name: slug.tr("_", " ").titleize, slug: slug)
      create(:role_permission, role: role, permission: permission)
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "keeps the expanded reports group subtle while strongly styling its active child" do
    visit hotel_reports_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] .panel-sidebar__group[data-state='open']")
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Financial")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger[aria-current='page']", visible: :all)
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Summary")
    end
  end

  it "clusters main navigation by staff role" do
    visit hotel_dashboard_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_link("Dashboard")
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Front Office")
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Planning & Inventory")
      expect(page).to have_css(".panel-sidebar__section-label", text: "Billing")
      expect(page).to have_css(".panel-sidebar__section-label", text: "Reports")

      within(".panel-sidebar__section[data-section-label='']") do
        expect(page).to have_link("Dashboard")
        expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Front Office")
        expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Planning & Inventory")
        expect(page).to have_link("Reservations", href: hotel_front_desk_path(hotel), visible: :all)
        expect(page).to have_link("Stay View", visible: :all)
        expect(page).to have_link("Requests", visible: :all)
        expect(page).to have_link("Night Audit", visible: :all)
        expect(page).to have_link("Rates & Inventory", visible: :all)
        expect(page).to have_link("Guest Records", visible: :all)
      end

      within(".panel-sidebar__section[data-section-label='Billing']") do
        expect(page).to have_link("Folios")
        expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Accounts Receivable")
        expect(page).to have_link("Payouts")
      end

      within(".panel-sidebar__section[data-section-label='Reports']") do
        expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Financial")
        expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Tax & Compliance")
        expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Accounting")
        expect(page).to have_link("Notification Logs", visible: :all)
      end

      expect(page).to have_no_link("Room Categories")
      expect(page).to have_no_link("Transaction Codes")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Guest Content")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Team Access")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "System Logs")
      expect(page).to have_no_link("Your Plan")
    end
  end

  it "renders report groups directly under the Reports section, without a wrapping dropdown" do
    visit hotel_reports_path(hotel)

    within("#hotel-sidebar") do
      within(".panel-sidebar__section[data-section-label='Reports']") do
        expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Financial")
        expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Tax & Compliance")
        expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Accounting")
        expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Reports")
      end
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Summary")
    end
  end

  it "opens the active report group directly, without a wrapping Reports dropdown" do
    visit hotel_reports_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Financial")
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Summary")
    end
  end

  it "separates clusters with dividers when collapsed" do
    driven_by(:cuprite)

    sign_in_through_ui(user)
    visit hotel_dashboard_path(hotel)
    find('button[aria-label="Collapse navigation"]').click

    expect(page).to have_css("#hotel-sidebar[data-collapsed='true']")
    within("#hotel-sidebar") do
      expect(page).to have_no_css(".panel-sidebar__section-label", visible: :visible)
    end
  end

  it "keeps daily operations as direct links and moves setup areas out of main nav" do
    visit hotel_dashboard_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_link("Dashboard", href: hotel_dashboard_path(hotel))
      expect(page).to have_link("Reservations", href: hotel_front_desk_path(hotel), visible: :all)
      expect(page).to have_link("Stay View", href: hotel_stay_view_path(hotel), visible: :all)
      expect(page).to have_link("Rates & Inventory", href: hotel_inventory_index_path(hotel), visible: :all)
      expect(page).to have_link("Guest Records", href: hotel_guests_path(hotel), visible: :all)
      expect(page).to have_link("Requests", href: hotel_requests_path(hotel), visible: :all)
      expect(page).to have_link("Folios", href: hotel_folios_path(hotel), visible: :all)
      expect(page).to have_link("Payouts", href: payouts_hotel_reports_path(hotel), visible: :all)
      expect(page).to have_no_link("Settings")
      expect(page).to have_no_link("Homepage")
      expect(page).to have_link("Night Audit", href: hotel_night_audits_path(hotel), visible: :all)

      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Front Office")
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Planning & Inventory")
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Accounts Receivable")
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Financial", visible: :all)
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Tax & Compliance", visible: :all)
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Accounting", visible: :all)
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Billing", visible: :all)
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Reports", visible: :all)
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "System Logs", visible: :all)

      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Stay View")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Rooms & Rates")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Guest Content")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Team Access")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "System Logs")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Cashiering")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Audit")
      expect(page).to have_no_link("Hotel Details", href: edit_hotel_profile_path(hotel), visible: :all)
      expect(page).to have_no_link("Taxes & Fees", href: hotel_taxes_fees_path(hotel), visible: :all)
      expect(page).to have_no_link("Audit", href: hotel_night_audits_path(hotel), visible: :all, exact: true)
      expect(page).to have_no_link("Room Categories", href: hotel_room_types_path(hotel), visible: :all)
      expect(page).to have_no_link("Transaction Codes", href: hotel_transaction_codes_path(hotel), visible: :all)
      expect(page).to have_no_link("Your Plan", href: hotel_plan_path(hotel), visible: :all)
      expect(page).to have_no_text("#<struct")

      expect(page).to have_css(".panel-sidebar__section-label", text: "Billing")
      expect(page).to have_css(".panel-sidebar__section-label", text: "Reports")
    end
  end


  it "uses the separate settings sidebar inside hotel settings" do
    visit hotel_dashboard_path(hotel)
    find("#hotel-profile-trigger").click
    within("#hotel-profile-menu") { click_link "Settings", href: hotel_general_settings_path(hotel) }

    within("#hotel-settings-sidebar") do
      expect(page).to have_no_link("Back to previous page")
      expect(page).to have_link("General", href: hotel_general_settings_path(hotel))
      expect(page).to have_link("Property", href: edit_hotel_profile_path(hotel))
      expect(page).to have_link("Finance", href: hotel_banking_details_settings_path(hotel))
      expect(page).to have_link("Guest Content", href: hotel_ai_concierge_settings_path(hotel))
      expect(page).to have_link("Team", href: hotel_users_path(hotel))
      expect(page).to have_css("a.panel-sidebar__link[aria-current='page']", text: "General")
      expect(page).to have_no_link("Dashboard", href: hotel_dashboard_path(hotel))
      expect(page).to have_no_link("Arrivals", href: hotel_arrivals_path(hotel))
    end
  end

  it "uses the settings sidebar for pages moved into Settings" do
    visit edit_hotel_profile_path(hotel)

    within("#hotel-settings-sidebar") do
      expect(page).to have_css("a.panel-sidebar__link[aria-current='page']", text: "Property")
      expect(page).to have_link("Property", href: edit_hotel_profile_path(hotel))
    end

    visit hotel_taxes_fees_path(hotel)

    within("#hotel-settings-sidebar") do
      expect(page).to have_css("a.panel-sidebar__link[aria-current='page']", text: "Finance")
      expect(page).to have_link("Finance", href: hotel_banking_details_settings_path(hotel))
    end
  end

  it "keeps wrapper groups visible when only a permissionless child is visible" do
    role.permissions.destroy_all

    visit hotel_dashboard_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_no_link("Settings", href: hotel_general_settings_path(hotel), visible: :all)
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Reports", visible: :all)
      expect(page).to have_no_link("Summary", href: hotel_reports_path(hotel), visible: :all)
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Guest Content", visible: :all)
      expect(page).to have_no_link("Policy Management", href: hotel_knowledge_policies_path(hotel), visible: :all)
    end
  end
end
