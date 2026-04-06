require 'rails_helper'

RSpec.describe 'Admin dashboard page', type: :system do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    driven_by(:rack_test)

    visit login_path
    fill_in 'Email address', with: superadmin.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In'
  end

  it 'shows the operational control center dashboard content' do
    visit admin_dashboard_path

    expect(page).to have_content('Operational Control Center')
    expect(page).to have_content('Hotels Pending Review')
    expect(page).to have_content('Failed Webhooks')
    expect(page).to have_content('Recent Confirmed Bookings')
    expect(page).to have_link('View analytics', href: admin_analytics_path)
  end
end
