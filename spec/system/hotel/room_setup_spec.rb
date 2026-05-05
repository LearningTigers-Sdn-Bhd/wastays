require 'rails_helper'

RSpec.describe 'Room Setup', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    driven_by(:rack_test)

    # Setup permissions and role
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    # Login
    visit login_path
    fill_in 'Email Address', with: user.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In to Portal'
  end

  it 'allows the user to add a room type' do
    expect(page).to have_content('Hotel Dashboard')
    within('#hotel-sidebar') { click_link 'Room Categories' }

    expect(page).to have_content('No room categories found')
    first(:link, 'Add Room Category').click

    fill_in 'Room Type Name', with: 'Deluxe Suite'
    fill_in 'FAQ', with: 'Is breakfast included? Yes.'
    fill_in 'Max Adults', with: 2
    fill_in 'Max Children', with: 1
    fill_in 'Total Number of Rooms', with: 5
    fill_in 'Base Nightly Rate (MYR)', with: 250

    click_button 'Create Room Type'

    expect(page).to have_content('Room type created successfully.')
    expect(page).to have_content('Deluxe Suite')
    expect(RoomType.order(:created_at).last.faq).to eq('Is breakfast included? Yes.')

    visit hotel_dashboard_path(hotel)
    expect(page).to have_content('Hotel Dashboard')
  end
end
