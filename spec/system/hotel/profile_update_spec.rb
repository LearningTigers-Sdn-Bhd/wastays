require 'rails_helper'

RSpec.describe 'Hotel Profile Update', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'registered') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    driven_by(:rack_test)
    
    # Setup permissions and role
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    
    # Login
    visit login_path
    fill_in 'Email', with: user.email
    fill_in 'Password', with: 'password123'
    click_button 'Login'
  end

  it 'allows the user to update the hotel profile' do
    expect(page).to have_content('Welcome to WAStays!')
    click_link 'Update'

    fill_in 'Hotel Name', with: 'Updated Hotel Name'
    fill_in 'Address', with: '123 New Street'
    select '5 Star', from: 'Star Rating'
    
    click_button 'Save Profile'

    expect(page).to have_content('Hotel profile updated successfully.')
    expect(hotel.reload.name).to eq('Updated Hotel Name')
    expect(hotel.status).to eq('profile_incomplete')
    
    # Onboarding should now show Step 1 as completed
    expect(page).to have_content('✓')
    expect(page).to have_link('Edit')
  end
end
