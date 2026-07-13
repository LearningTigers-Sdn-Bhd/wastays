require 'rails_helper'

RSpec.describe 'Hotel layout shell', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin', email: 'owner@example.com') }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, plan: plan, status: 'approved') }
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
    expect(page).to have_css(
      "#hotel-sidebar .panel-sidebar__header a[aria-label='Hotel: #{hotel.name}']"
    )
    expect(page).to have_link('Arrivals', href: hotel_arrivals_path(hotel), visible: :all)
    expect(page).to have_link('Bookings', href: hotel_bookings_path(hotel), visible: :all)
    expect(page).to have_link('In-House Guests', href: hotel_in_house_guests_path(hotel), visible: :all)
    expect(page).to have_link('Rates & Inventory', href: hotel_inventory_index_path(hotel), visible: :all)
    expect(page).to have_link('Guest Records', href: hotel_guests_path(hotel), visible: :all)
    expect(page).to have_no_link('Hotel Details', href: edit_hotel_profile_path(hotel), visible: :all)
    expect(page).to have_no_link('Room Categories', href: hotel_room_types_path(hotel), visible: :all)
    expect(page).to have_no_link('Nearby Attractions', href: hotel_nearby_attractions_path(hotel), visible: :all)
    expect(page).to have_text('Reports')
    expect(page).to have_link('Summary', href: hotel_reports_path(hotel), visible: :all)
    expect(page).to have_link('Night Audit', href: hotel_night_audits_path(hotel), visible: :all)
    expect(page).to have_css('#toast-viewport[data-controller="toast"]')
    expect(page).to have_css("#hotel-sidebar a.panel-sidebar__link[data-sidebar-route][aria-current='page']", text: "Dashboard")
    expect(page).to have_css("#hotel-sidebar button.panel-sidebar__group-trigger", text: "Financial", visible: :all)
    expect(page).to have_no_css("#hotel-sidebar button.panel-sidebar__group-trigger[aria-current='page']", visible: :all)
  end
end
