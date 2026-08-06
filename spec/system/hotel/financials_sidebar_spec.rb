# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel financials layer sidebar", type: :system do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account) }

  before do
    driven_by(:cuprite)

    %w[view_reports view_bookings manage_corporate_accounts].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.tr("_", " ").titleize, slug: slug)
      create(:role_permission, role: role, permission: permission)
    end
    create(:user_hotel_access, user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  # The rail renders collapsed, which hides section labels and group children
  # behind `display: none`. Lock it open so these assertions describe what a
  # reader of the sidebar actually sees.
  def lock_navigation_open
    find('button[aria-label="Lock navigation open"]').click
    expect(page).to have_css("#hotel-financials-sidebar[data-collapsed='false'][data-locked='true']")
  end

  it "carries folios and the receivables tree, and none of the operations nav" do
    visit hotel_folios_path(hotel)
    lock_navigation_open

    expect(page).to have_no_css("#hotel-sidebar", visible: :all)

    within("#hotel-financials-sidebar") do
      expect(page).to have_link("Folios", href: hotel_folios_path(hotel))
      expect(page).to have_css(".panel-sidebar__section-label", text: /Billing/i)
      expect(page).to have_css("button.panel-sidebar__group-trigger", text: "Cashiering")
      expect(page).to have_link("Invoices", href: hotel_ar_invoices_path(hotel), visible: :all)
      expect(page).to have_link("External Accounts", href: hotel_corporate_accounts_path(hotel), visible: :all)

      expect(page).to have_no_link("Dashboard")
      expect(page).to have_no_css("button.panel-sidebar__group-trigger", text: "Front Office")
      expect(page).to have_no_css(".panel-sidebar__section-label", text: /Reports/i)
    end
  end

  it "marks the active receivables page and opens its group" do
    visit hotel_ar_invoices_path(hotel)
    lock_navigation_open

    within("#hotel-financials-sidebar") do
      expect(page).to have_css("a.panel-sidebar__child[aria-current='page']", text: "Invoices")
      expect(page).to have_css("[data-sidebar-group-item][data-sidebar-active] button.panel-sidebar__group-trigger[aria-expanded='true']", text: "Cashiering")
    end
  end

  it "keeps the portal header pointing back at the operations dashboard" do
    visit hotel_folios_path(hotel)

    within("#hotel-financials-sidebar") do
      expect(page).to have_link("Hotel Portal", href: hotel_dashboard_path(hotel))
    end
  end
end
