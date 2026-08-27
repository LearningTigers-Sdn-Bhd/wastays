require 'rails_helper'

RSpec.describe 'Room Setup', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'live') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    # Setup permissions and role
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    # Login
    sign_in_through_ui(user)
  end

  it 'allows the user to add a room category from Room Inventory' do
    visit hotel_room_types_path(hotel)

    expect(page).to have_content('No room categories found')
    first(:link, 'Create room category').click

    # Every section is on one scrollable sheet now — no tab to click through.
    fill_in 'Room Category Name', with: 'Deluxe Suite'
    fill_in 'Max Adults', with: 2
    fill_in 'Max Children', with: 1
    fill_in 'Total Number of Rooms', with: 5
    fill_in 'Standard Rate (MYR)', with: 250

    click_button 'Create Room Category'

    expect(page).to have_content('Room category created successfully.')
    expect(page).to have_content('Deluxe Suite')
    expect(page).to have_css(".panel-collapsible[data-state='closed']", text: 'Deluxe Suite')
    click_link 'Assign room rate'

    within '#assign-room-rate-sheet' do
      expect(page).to have_css('.panel-autocomplete', text: '')
      expect(page).to have_css('.panel-multi-select', text: 'Deluxe Suite')
      expect(page).to have_no_content('Guest pricing')
      click_button 'Cancel'
    end

    visit hotel_dashboard_path(hotel)
    expect(page).to have_current_path(hotel_dashboard_path(hotel))
    expect(page).to have_content('Rates & Inventory')
  end
end
