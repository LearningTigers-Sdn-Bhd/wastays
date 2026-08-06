require 'rails_helper'
require 'securerandom'

RSpec.describe 'Admin mobile sidebar', type: :system do
  self.use_transactional_tests = false

  let(:token) { SecureRandom.hex(6) }
  let!(:account) { create(:account, name: "Sidebar Search #{token}") }
  let!(:superadmin) { create(:user, :superadmin, account: account, email: "sidebar-search-#{token}@example.com") }

  after do
    User.where(id: superadmin.id).delete_all
    Account.where(id: account.id).delete_all
  end

  before do
    driven_by(:cuprite)

    sign_in_through_ui(superadmin)
    expect(page).to have_current_path(admin_dashboard_path, ignore_query: true)
    page.current_window.resize_to(390, 844) if Capybara.current_driver != :rack_test
  end

  it 'opens from the mobile toggle and lets the user navigate to audit logs' do
    find('button[aria-label="Open navigation"]').click

    within('#admin-sidebar-mobile') do
      audit_link = find("a[href='#{admin_audit_logs_path}']", text: 'Audit Logs', visible: :all)
      audit_link.click
    end

    expect(page).to have_current_path(admin_audit_logs_path, ignore_query: true)
    expect(page).to have_content('Audit Logs')
  end
end
