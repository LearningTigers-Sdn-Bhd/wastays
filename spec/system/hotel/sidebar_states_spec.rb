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
    %w[arrivals_departures_list room_status_board unified_guest_profile task_assignment_minibar_log no_show_auto_handling].each do |slug|
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

  it "clusters main navigation by staff role" do
    visit hotel_dashboard_path(hotel)

    within("#hotel-sidebar") do
      expect(page).to have_link("Dashboard")
      # Operations is flat: sections carry the grouping, no dropdowns at all.
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", visible: :all)
      expect(page).to have_css(".panel-sidebar__section-label", text: /Front Desk/i)
      expect(page).to have_css(".panel-sidebar__section-label", text: /Housekeeping/i)
      expect(page).to have_css(".panel-sidebar__section-label", text: /Planning/i)
      expect(page).to have_css(".panel-sidebar__section-label", text: /Day Close/i)
      expect(page).to have_no_css(".panel-sidebar__section-label", text: "Billing")
      expect(page).to have_no_css(".panel-sidebar__section-label", text: "Reports")
      expect(page).to have_css(".panel-sidebar__section-label", text: "More")

      within(".panel-sidebar__section[data-section-label='Front Desk']") do
        expect(page).to have_link("Reservations", href: hotel_front_desk_path(hotel))
        expect(page).to have_link("Stay View")
        expect(page).to have_link("Guest Records")
      end

      # This role holds manage_requests but not the housekeeping-task grants.
      within(".panel-sidebar__section[data-section-label='Housekeeping']") do
        expect(page).to have_link("Requests")
      end

      within(".panel-sidebar__section[data-section-label='Planning']") do
        expect(page).to have_link("Rates & Inventory")
      end

      within(".panel-sidebar__section[data-section-label='Day Close']") do
        expect(page).to have_link("Run Night Audit")
      end

      # Cashiering and Folios live in the financials layer now; operations only
      # keeps the door to it, which opens in its own tab.
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Cashiering")
      expect(page).to have_no_link("Payouts")
      within(".panel-sidebar__section[data-section-label='More']") do
        expect(page).to have_link("Financials", href: hotel_folios_path(hotel))
        expect(page).to have_link("Reports", href: hotel_reports_path(hotel))
        expect(page).to have_css("a[href='#{hotel_folios_path(hotel)}'][target='_blank'][rel='noopener noreferrer']")
        expect(page).to have_css("a[href='#{hotel_reports_path(hotel)}'][target='_blank'][rel='noopener noreferrer']")

        # Leaving the tab is worth saying before the click, not after.
        expect(page).to have_css("a[href='#{hotel_folios_path(hotel)}'] svg.panel-sidebar__external")
        expect(page).to have_css("a[href='#{hotel_reports_path(hotel)}'] svg.panel-sidebar__external")
        expect(page).to have_css("a[href='#{hotel_reports_path(hotel)}'] .sr-only", text: "(opens in a new tab)", visible: :all)
      end

      # Rows that stay in this tab say nothing.
      expect(page).to have_no_css("a[href='#{hotel_dashboard_path(hotel)}'] svg.panel-sidebar__external")

      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Financial")
      expect(page).to have_no_link("Tax & Compliance", href: tax_compliance_hotel_reports_path(hotel))
      expect(page).to have_no_link("Notification Logs", visible: :all)

      expect(page).to have_no_link("Room Inventory")
      expect(page).to have_no_link("Transaction Code Reference")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Guest Content")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Team Access")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "System Logs")
      expect(page).to have_no_link("Your Plan")
    end
  end

  it "separates clusters with dividers when collapsed" do
    driven_by(:cuprite)

    sign_in_through_ui(user)
    visit hotel_dashboard_path(hotel)

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
      expect(page).to have_no_link("Folios", href: hotel_folios_path(hotel), visible: :all)
      expect(page).to have_no_link("Payouts", href: payouts_hotel_reports_path(hotel), visible: :all)
      expect(page).to have_no_link("Settings")
      expect(page).to have_no_link("Homepage")
      expect(page).to have_link("Run Night Audit", visible: :all)
      expect(page).to have_no_link("Night Audit History", href: hotel_reports_night_audits_path(hotel), visible: :all)

      expect(page).to have_no_css("button.panel-sidebar__group-trigger", visible: :all)
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Cashiering")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Financial", visible: :all)
      expect(page).to have_no_link("Tax & Compliance", href: tax_compliance_hotel_reports_path(hotel), visible: :all)
      expect(page).to have_no_link("Guest Reports", href: guest_reports_hotel_reports_path(hotel), visible: :all)
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Billing", visible: :all)
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Reports", visible: :all)
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "System Logs", visible: :all)

      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Stay View")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Rooms & Rates")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Guest Content")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Team Access")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "System Logs")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Audit")
      expect(page).to have_no_link("Hotel Details", href: edit_hotel_profile_path(hotel), visible: :all)
      expect(page).to have_no_link("Taxes & Fees", href: hotel_taxes_fees_path(hotel), visible: :all)
      expect(page).to have_no_link("Audit", href: hotel_night_audits_path(hotel), visible: :all, exact: true)
      expect(page).to have_no_link("Room Inventory", href: hotel_room_types_path(hotel), visible: :all)
      expect(page).to have_no_link("Transaction Code Reference", href: hotel_transaction_code_references_path(hotel), visible: :all)
      expect(page).to have_no_link("Your Plan", href: hotel_plan_path(hotel), visible: :all)
      expect(page).to have_no_text("#<struct")

      expect(page).to have_no_css(".panel-sidebar__section-label", text: "Billing")
      expect(page).to have_no_css(".panel-sidebar__section-label", text: "Reports")
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
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-label='Commercial']", visible: :all)
      expect(page).to have_link("Taxes & Fees", href: hotel_taxes_fees_path(hotel), visible: :all)
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
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-label='Commercial']", visible: :all)
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Taxes & Fees", visible: :all)
      expect(page).to have_link("Taxes & Fees", href: hotel_taxes_fees_path(hotel), visible: :all)
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
