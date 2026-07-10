require 'rails_helper'

RSpec.describe 'Hotel Profile Update', type: :system, js: true do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    driven_by(:cuprite)

    # Setup permissions and role
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    # Login
    sign_in_through_ui(user)
  end

  it 'allows the user to update the hotel profile' do
    visit hotel_dashboard_path(hotel)
    within('#hotel-sidebar') { click_link 'Hotel Details' }

    within('#hotel-profile-section') do
      fill_in 'Hotel Name', with: 'Updated Hotel Name'
      fill_in 'Address', with: '123 New Street'
      click_button 'Save Profile'
    end

    expect(page).to have_content('Hotel profile updated successfully.')
    expect(hotel.reload.name).to eq('Updated Hotel Name')
    expect(page).to have_current_path(edit_hotel_profile_path(hotel))
    expect(page).not_to have_css('#hotel-faq-section')
  end
end
