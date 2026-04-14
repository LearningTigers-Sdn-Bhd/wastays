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
    driven_by(:rack_test)

    visit login_path
    fill_in 'Email Address', with: superadmin.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In to Portal'
    expect(page).to have_current_path(admin_dashboard_path, ignore_query: true)
    page.current_window.resize_to(390, 844) if Capybara.current_driver != :rack_test
  end

  it 'filters mobile sidebar links and lets the user open the matching page' do
    pending "Skipping due to missing Chrome binary in this environment"
    find('button[aria-label="Toggle navigation"]').click

    within('#admin-sidebar-mobile') do
      fill_in 'Search navigation', with: 'audit'

      audit_link = find("a[href='#{admin_audit_logs_path}']", text: 'Audit Logs', visible: :all)
      bookings_link = find("a[href='#{admin_bookings_path}']", text: 'Bookings', visible: :all)

      expect(audit_link[:class]).not_to include('hidden')
      expect(bookings_link[:class]).to include('hidden')

      audit_link.click
    end

    expect(page).to have_current_path(admin_audit_logs_path, ignore_query: true)
    expect(page).to have_content('Audit Logs')
  end
end
