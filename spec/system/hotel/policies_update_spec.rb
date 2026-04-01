require 'rails_helper'

RSpec.describe 'Hotel Policies Update', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'profile_incomplete') }
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

  it 'allows the user to update the hotel policies' do
    expect(page).to have_content('Hotel Profile')

    # Click Update for Step 2
    within('#step-policies') do
      click_link 'Update'
    end

    fill_in 'Standard Check-in Time', with: '3:00 PM'
    fill_in 'Standard Check-out Time', with: '11:00 AM'
    fill_in 'Cancellation Policy', with: 'Full refund if cancelled 24h before.'

    click_button 'Save Policies'

    expect(page).to have_content('Hotel policies updated successfully.')
    expect(hotel.reload.status).to eq('rooms_incomplete')
    expect(hotel.property_policy.check_in_time).to eq('3:00 PM')

    # Onboarding should now show Step 2 as completed
    within('#step-policies') do
      expect(page).to have_content('✓')
      expect(page).to have_link('Edit')
    end
  end
end
