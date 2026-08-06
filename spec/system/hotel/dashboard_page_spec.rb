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

    sign_in_through_ui(user)
  end

  it 'shows the hotel dashboard content' do
    visit hotel_dashboard_path(hotel)

    expect(page).to have_content('Revenue (This Month)')
    expect(page).to have_content('Arrival Board')
    expect(page).to have_content('7-Day Occupancy')
    expect(page).to have_content('Recent Bookings')
    expect(page).to have_link('Go to Front Desk Bookings', href: hotel_front_desk_path(hotel, tab: "bookings", view: "rooms"))
    expect(page.body.index('Arrival Board')).to be < page.body.index('Recent Bookings')
  end
end
