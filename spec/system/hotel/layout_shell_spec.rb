require 'rails_helper'

RSpec.describe 'Hotel layout shell', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin', email: 'owner@example.com') }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) do
    create(
      :hotel,
      account: account,
      plan: plan,
      name: "O'Conner Hotel",
      status: 'live',
      sell_mode: RSpec.current_example.metadata[:per_person] ? 'per_person' : 'per_room'
    )
  end
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }

  before do
    driven_by(:rack_test)

    # Ensure all permissions exist and assign them to the role
    [
      "manage_guest_arrival", "view_bookings", "manage_room_status", "manage_requests",
      "manage_hotel_profile", "manage_users", "view_reports", "view_payouts", "view_audit_logs",
      "manage_night_audit", "view_guest_records"
    ].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.titleize, slug: slug)
      role.permissions << permission unless role.permissions.include?(permission)
    end

    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    %w[unified_guest_profile no_show_auto_handling].each do |slug|
      create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: slug), enabled: true)
    end

    sign_in_through_ui(user)
  end

  it 'renders the hotel navigation shell for approved hotel owners' do
    visit hotel_dashboard_path(hotel)

    expect(page).to have_link('Dashboard', href: hotel_dashboard_path(hotel))
    within("#hotel-sidebar .panel-sidebar__header") do
      portal_link = find_link("Hotel Portal", href: hotel_dashboard_path(hotel))
      expect(portal_link["aria-label"]).to eq("Hotel Portal")
      # The icon is the only thing left identifying the portal once the rail
      # collapses and the label is hidden.
      expect(portal_link).to have_css("svg.panel-sidebar__icon")
    end
    expect(page).to have_css('.panel-sidebar__section-label', text: /Front Desk/i)
    expect(page).to have_link('Reservations', href: hotel_front_desk_path(hotel), visible: :all)
    expect(page).to have_link('Rates & Inventory', href: hotel_inventory_index_path(hotel), visible: :all)
    expect(page).to have_link('Guest Records', href: hotel_guests_path(hotel), visible: :all)
    expect(page).to have_no_link('Hotel Details', href: edit_hotel_profile_path(hotel), visible: :all)
    expect(page).to have_no_link('Room Inventory', href: hotel_room_types_path(hotel), visible: :all)
    expect(page).to have_no_link('Nearby Attractions', href: hotel_nearby_attractions_path(hotel), visible: :all)
    # Reports is a layer of its own now: operations carries the door, not the
    # individual report pages.
    expect(page).to have_link('Reports', href: hotel_reports_path(hotel), visible: :all)
    expect(page).to have_link('Financials', href: hotel_folios_path(hotel), visible: :all)
    expect(page).to have_no_link('Summary', href: hotel_reports_path(hotel), visible: :all)
    expect(page).to have_link('Run Night Audit', href: hotel_night_audit_run_path(hotel), visible: :all)
    expect(page).to have_no_link('Night Audit History', href: hotel_reports_night_audits_path(hotel), visible: :all)
    expect(page).to have_css('#toast-viewport[data-controller="toast"]')
    expect(page).to have_css("header.panel-navbar[data-sticky='true']")
    expect(page).to have_css(".panel-navbar__center [data-controller='panels-ui--command-palette']")
    within(".panel-navbar__brand") do
      identity = find_link(hotel.name, href: hotel_dashboard_path(hotel))
      expect(identity).to have_css(".panel-navbar__identity-meta", text: hotel.unique_id)
      expect(page).to have_css("[data-testid='hotel-sell-mode-badge']", text: "Sells per room")
    end
    expect(page).to have_css("#hotel-profile a[href='#{help_center_path}']", text: "Help")
    expect(page).to have_css(".panel-navbar__actions button[aria-label='Announcements'][aria-expanded='false']")
    expect(page).to have_css("#announcements-panel", text: "There are no announcements right now.", visible: :all)
    expect(page).to have_css(".panel-navbar__actions button[aria-label='Notifications'][aria-expanded='false']")
    expect(page).to have_css("#notifications-panel", text: "You have no notifications right now.", visible: :all)
    expect(page).to have_css("#hotel-profile[data-controller='panels-ui--dropdown-menu']")
    expect(page).to have_css("button[command='show-modal'][commandfor='hotel-sidebar-mobile']")
    expect(page).to have_no_css("nav[aria-label='Mobile navigation']", visible: :all)
    expect(page).to have_css("#hotel-sidebar a.panel-sidebar__link[data-sidebar-route][aria-current='page']", text: "Dashboard")
    # Operations is flat, so it has no group triggers left to style.
    expect(page).to have_no_css("#hotel-sidebar button.panel-sidebar__group-trigger", visible: :all)
  end

  it "names the per-person sell mode in the Navbar badge", :per_person do
    visit hotel_dashboard_path(hotel)

    within(".panel-navbar__brand") do
      expect(page).to have_css("[data-testid='hotel-sell-mode-badge']", text: "Sells per person")
    end
  end

  it "renders the onboarding Navbar while the hotel is pending review" do
    hotel.update!(status: "pending_review")

    visit hotel_dashboard_path(hotel)

    expect(page).to have_css("header.panel-navbar")
    expect(page).to have_no_css(".panel-navbar__center", visible: :all)
    expect(page).to have_css("#onboarding-profile[data-controller='panels-ui--dropdown-menu']")
    expect(page).to have_no_css("#hotel-sidebar", visible: :all)
    expect(page).to have_no_css("button[command='show-modal'][commandfor='hotel-sidebar-mobile']", visible: :all)
    expect(page).to have_no_css("[data-controller='panels-ui--sidebar-toggle']", visible: :all)
  end
end
