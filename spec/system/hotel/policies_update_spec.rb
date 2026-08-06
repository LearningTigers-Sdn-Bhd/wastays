require 'rails_helper'

RSpec.describe 'Hotel Policies Update', type: :system do
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
    sign_in_through_ui(user)
  end

  it 'allows the user to update the hotel policies' do
    # Navigate directly to the edit page as there is no sidebar link
    visit edit_hotel_property_policy_path(hotel)

    expect(page).to have_content('Hotel Policies')
    expect(page).to have_field('Standard Check-in Time')
    expect(page).to have_field('Standard Check-out Time')

    # Cancellation terms moved to the structured reservation policy — this page
    # no longer offers a free-text box for them.
    expect(page).to have_no_field('property_policy[cancellation_policy]')
    expect(page).to have_content('Reservation policies')

    fill_in 'Standard Check-in Time', with: '15:00'
    fill_in 'Standard Check-out Time', with: '11:00'

    click_button 'Save Policies'

    expect(page).to have_content('Hotel policies updated successfully.')
    expect(hotel.property_policy.reload.check_in_time).to eq('15:00')
    expect(page).to have_current_path(hotel_dashboard_path(hotel))
    expect(page).to have_content('Hotel Portal')
  end

  it 'denies access without the manage_hotel_profile permission' do
    role.permissions.delete_all

    visit edit_hotel_property_policy_path(hotel)

    expect(page).to have_current_path(root_path)
    expect(page).to have_content('You are not authorized to perform this action.')
  end
end
