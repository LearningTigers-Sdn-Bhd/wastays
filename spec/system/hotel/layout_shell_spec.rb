require 'rails_helper'

RSpec.describe 'Hotel layout shell', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin', email: 'owner@example.com') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }

  before do
    driven_by(:rack_test)

    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in 'Email Address', with: user.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In to Portal'
  end

  it 'renders the hotel navigation shell for approved hotel owners' do
    visit hotel_dashboard_path(hotel)

    expect(page).to have_link('Dashboard', href: hotel_dashboard_path(hotel))
    expect(page).to have_link('Arrivals', href: hotel_arrivals_path(hotel))
    expect(page).to have_link('Bookings', href: hotel_bookings_path(hotel))
    expect(page).to have_link('Rates & Inventory', href: hotel_inventory_index_path(hotel))
    expect(page).to have_link('Guests', href: hotel_guests_path(hotel))
    expect(page).to have_link('Reports', href: hotel_reports_path(hotel))
    expect(page).to have_content('Rooms')
    expect(page).to have_css('#flash_toasts')
    expect(page).to have_link('My account', href: edit_hotel_user_profile_path(hotel))
  end
end
