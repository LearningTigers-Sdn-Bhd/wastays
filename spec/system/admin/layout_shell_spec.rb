require 'rails_helper'

RSpec.describe 'Admin layout shell', type: :system do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    driven_by(:rack_test)

    sign_in_through_ui(superadmin)
  end

  it 'renders the admin navigation shell for superadmins' do
    visit admin_dashboard_path

    expect(page).to have_content('Dashboard')
    expect(page).to have_link('Dashboard', href: admin_dashboard_path)
    expect(page).to have_link('Hotels', href: admin_hotels_path)
    expect(page).to have_link('Bookings', href: admin_bookings_path)
    expect(page).to have_link('Audit Logs', href: admin_audit_logs_path)
    expect(page).to have_css("#admin-profile a[href='#{help_center_path}']", text: 'Help')
    expect(page).to have_no_css(".panel-navbar__actions a[href='#{help_center_path}']")
    expect(page).to have_link('Homepage', href: root_path)
    expect(page).to have_link('Payment Issues', href: admin_reconciliation_dashboard_path)
    expect(page).to have_link('My account', href: edit_admin_profile_path)
    expect(page).to have_link('Admin Panel', href: admin_dashboard_path)
    expect(page).to have_css("header.panel-navbar[data-sticky='true']")
    expect(page).to have_css("#admin-profile[data-controller='panels-ui--dropdown-menu']")
    expect(page).to have_css("button[command='show-modal'][commandfor='admin-sidebar-mobile']")
    expect(page).to have_no_css("nav[aria-label='Mobile navigation']", visible: :all)
    expect(page).to have_css("#admin-sidebar a.panel-sidebar__link[data-sidebar-route][aria-current='page']", text: "Dashboard")
    expect(page).to have_css("#admin-sidebar [data-sidebar-presentation='collapsed']", visible: :all)
    expect(page).to have_no_css("#admin-sidebar a.panel-sidebar__link.text-red-600[aria-current='page']")
  end
end
