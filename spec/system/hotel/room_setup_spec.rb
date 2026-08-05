require 'rails_helper'

RSpec.describe 'Room Setup', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    # Setup permissions and role
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    # Login
    sign_in_through_ui(user)
  end

  it 'allows the user to add a room type' do
    visit hotel_room_types_path(hotel)

    expect(page).to have_content('No room categories found')
    first(:link, 'Create Room Category').click

    # Every section is on one scrollable sheet now — no tab to click through.
    fill_in 'Room Category Name', with: 'Deluxe Suite'
    fill_in 'Max Adults', with: 2
    fill_in 'Max Children', with: 1
    fill_in 'Total Number of Rooms', with: 5
    fill_in 'Standard Rate (MYR)', with: 250

    click_button 'Create Room Category'

    expect(page).to have_content('Room category created successfully.')
    expect(page).to have_content('Deluxe Suite')

    visit hotel_dashboard_path(hotel)
    expect(page).to have_content('Hotel Portal')
  end
end
