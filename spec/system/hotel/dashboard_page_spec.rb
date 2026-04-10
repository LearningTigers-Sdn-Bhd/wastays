require 'rails_helper'

RSpec.describe 'Hotel dashboard page', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin', email: 'owner@example.com') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }

  before do
    driven_by(:rack_test)

    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in 'Email address', with: user.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In'
  end

  it 'shows the hotel dashboard content' do
    visit hotel_dashboard_path(hotel)

    expect(page).to have_content('Dashboard')
    expect(page).to have_content('Arrival Board')
    expect(page).to have_content('Action Required')
    expect(page).to have_content('7-Day Occupancy')
    expect(page).to have_content('Recent Bookings')
    expect(page).to have_link('View all bookings', href: hotel_bookings_path(hotel))
  end
end
