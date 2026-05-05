require 'rails_helper'

RSpec.describe 'Hotel Profile Update', type: :system do
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

  it 'allows the user to update the hotel profile' do
    expect(page).to have_content('Hotel Dashboard')
    within('#hotel-sidebar') { click_link 'Hotel Details' }

    fill_in 'Hotel Name', with: 'Updated Hotel Name'
    fill_in 'Address', with: '123 New Street'

    click_button 'Save Profile'

    expect(page).to have_content('Hotel profile updated successfully.')
    expect(hotel.reload.name).to eq('Updated Hotel Name')
    expect(page).to have_content('Hotel Dashboard')
  end

  it 'allows the user to save the hotel faq independently' do
    visit edit_hotel_profile_path(hotel)

    fill_in 'hotel_faq', with: 'Do you offer airport transfers? Yes, on request.'
    click_button 'Save FAQ'

    expect(page).to have_content('Hotel profile updated successfully.')
    expect(hotel.reload.faq).to include('airport transfers')
  end

  it 'allows the user to save the hotel policy independently' do
    visit edit_hotel_profile_path(hotel)

    fill_in 'hotel_policy', with: 'Quiet hours start at 10 PM.'
    click_button 'Save Policy'

    expect(page).to have_content('Hotel profile updated successfully.')
    expect(hotel.reload.policy).to include('Quiet hours')
  end
end
