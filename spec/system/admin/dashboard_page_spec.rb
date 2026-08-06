require 'rails_helper'

RSpec.describe 'Admin dashboard page', type: :system do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    driven_by(:rack_test)

    sign_in_through_ui(superadmin)
  end

  it 'shows the current admin dashboard content' do
    visit admin_dashboard_path

    expect(page).to have_content('Dashboard')
    expect(page).to have_content('Platform overview and real-time operational status.')
    expect(page).to have_content('Payment Sync Status')
    expect(page).to have_content('Recent Successful Bookings')
    expect(page).to have_link('View All Bookings', href: admin_bookings_path)
  end
end
