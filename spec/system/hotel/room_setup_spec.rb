require 'rails_helper'

RSpec.describe 'Room Setup', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'rooms_incomplete') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    driven_by(:rack_test)
    
    # Setup permissions and role
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    
    # Login
    visit login_path
    fill_in 'Email address', with: user.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In'
  end

  it 'allows the user to add a room type' do
    expect(page).to have_content('Hotel Policies')
    expect(page).to have_content('✓')
    
    # Click Update for Step 3
    within('#step-rooms') do
      click_link 'Update'
    end

    expect(page).to have_content('No room types found')
    first(:link, 'Add Room Type').click

    fill_in 'Room Type Name', with: 'Deluxe Suite'
    fill_in 'Max Adults', with: 2
    fill_in 'Max Children', with: 1
    fill_in 'Total Number of Rooms', with: 5
    fill_in 'Base Nightly Rate (MYR)', with: 250
    
    click_button 'Create Room Type'

    expect(page).to have_content('Room type created successfully.')
    expect(page).to have_content('Deluxe Suite')
    expect(hotel.reload.status).to eq('inventory_incomplete')
    
    # Go back to dashboard to check onboarding
    click_link 'Back to Dashboard'
    within('#step-rooms') do
      expect(page).to have_content('✓')
      expect(page).to have_link('Manage')
    end
    
    # Step 4 Submit button should now be enabled
    within('#step-review') do
      expect(page).to have_button('Submit for Review')
    end
  end
end
