# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel reports layer sidebar", type: :system do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    driven_by(:rack_test)
    %w[arrivals_departures_list no_show_auto_handling full_audit_trail].each do |slug|
      create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: slug), enabled: true)
    end

    %w[view_reports view_bookings view_audit_logs manage_night_audit].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.tr("_", " ").titleize, slug: slug)
      create(:role_permission, role: role, permission: permission)
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it "renders four report groups without a wrapping Reports dropdown" do
    visit hotel_reports_path(hotel)

    expect(page).to have_no_css("#hotel-sidebar", visible: :all)

    within("#hotel-reports-sidebar") do
      # Four groups, no wrapping "Reports" dropdown and no section labels.
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Financial")
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Compliance")
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Guest")
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Logs")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Reports")
      expect(page).to have_link("Tax & Compliance", href: tax_compliance_hotel_reports_path(hotel), visible: :all)
      expect(page).to have_link("Guest Reports", href: guest_reports_hotel_reports_path(hotel), visible: :all)
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Summary")
    end
  end

  it "opens the active report group directly, without a wrapping Reports dropdown" do
    visit hotel_reports_path(hotel)

    within("#hotel-reports-sidebar") do
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Financial")
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Summary")
    end
  end

  it "keeps the expanded reports group subtle while strongly styling its active child" do
    visit hotel_reports_path(hotel)

    within("#hotel-reports-sidebar") do
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] .panel-sidebar__group[data-state='open']")
      expect(page).to have_css("button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Financial")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger[aria-current='page']", visible: :all)
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Summary")
    end
  end

  # These three had no sidebar entry anywhere before the split -- they were
  # reachable only from the command palette or a saved link.
  it "gives the previously unreachable report pages a home" do
    visit hotel_reports_path(hotel)

    within("#hotel-reports-sidebar") do
      expect(page).to have_link("Payouts", href: payouts_hotel_reports_path(hotel), visible: :all)
      expect(page).to have_link("Daily Performance Breakdown", href: breakdown_hotel_reports_path(hotel), visible: :all)
      expect(page).to have_link("Inventory Audit Logs", href: hotel_inventory_audit_logs_path(hotel), visible: :all)
    end
  end

  it "gathers the log pages into their own group and leaves operations behind" do
    visit hotel_audit_logs_path(hotel)

    within("#hotel-reports-sidebar") do
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Logs")
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Operation Logs")
      expect(page).to have_link("Notification Logs", href: hotel_notification_logs_path(hotel), visible: :all)

      expect(page).to have_no_link("Dashboard", href: hotel_dashboard_path(hotel))
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Front Office")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Cashiering")
    end
  end

  it "keeps the portal header pointing back at the operations dashboard" do
    visit hotel_reports_path(hotel)

    within("#hotel-reports-sidebar") do
      expect(page).to have_link("Hotel Portal", href: hotel_dashboard_path(hotel))
    end
  end
end
