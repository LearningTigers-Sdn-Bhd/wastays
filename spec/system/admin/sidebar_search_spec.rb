require 'rails_helper'
require 'securerandom'

RSpec.describe 'Admin sidebar search', type: :system do
  self.use_transactional_tests = false

  let(:token) { SecureRandom.hex(6) }
  let!(:account) { create(:account, name: "Sidebar Search #{token}") }
  let!(:superadmin) { create(:user, :superadmin, account: account, email: "sidebar-search-#{token}@example.com") }

  after do
    User.where(id: superadmin.id).delete_all
    Account.where(id: account.id).delete_all
  end

  before do
    driven_by(:selenium, using: :headless_chrome, screen_size: [390, 844])

    visit login_path
    fill_in 'Email address', with: superadmin.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In'
    expect(page).to have_current_path(admin_dashboard_path, ignore_query: true)
  end

  it 'filters mobile sidebar links and lets the user open the matching page' do
    find('button[aria-label="Toggle navigation"]').click

    within('#admin-sidebar-mobile') do
      fill_in 'Search navigation', with: 'audit'
      expect(page).to have_link('Audit Logs', href: admin_audit_logs_path)
      expect(page).to have_no_link('Bookings', href: admin_bookings_path)
      click_link 'Audit Logs'
    end

    expect(page).to have_current_path(admin_audit_logs_path, ignore_query: true)
    expect(page).to have_content('Audit Logs')
  end
end
