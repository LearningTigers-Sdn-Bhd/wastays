require 'rails_helper'

RSpec.describe 'Admin layout shell', type: :system do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    driven_by(:rack_test)

    visit login_path
    fill_in 'Email Address', with: superadmin.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In to Portal'
  end

  it 'renders the admin navigation shell for superadmins' do
    visit admin_dashboard_path

    expect(page).to have_content('Dashboard')
    expect(page).to have_link('Dashboard', href: admin_dashboard_path)
    expect(page).to have_link('Hotels', href: admin_hotels_path)
    expect(page).to have_link('Bookings', href: admin_bookings_path)
    expect(page).to have_link('Audit Logs', href: admin_audit_logs_path)
    expect(page).to have_link('Help', href: help_center_path)
    expect(page).to have_link('Homepage', href: root_path)
    expect(page).to have_link('Payment Issues', href: admin_reconciliation_dashboard_path)
    expect(page).to have_link('My account', href: edit_admin_profile_path)
  end
end
