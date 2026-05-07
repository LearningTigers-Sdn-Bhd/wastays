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
    visit login_path
    fill_in 'Email Address', with: user.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In to Portal'
  end

  it 'allows the user to update the hotel profile' do
    expect(page).to have_content('Hotel Dashboard')
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

  it 'allows the user to save the hotel faq independently' do
    visit edit_hotel_faq_path(hotel)

    within('#hotel-faq-form') do
      click_button 'Add Section'

      # Fill section name
      find('input[placeholder="e.g., Arrival & Check-in"]').set('General')

      # Fill question and answer
      find('input[placeholder="Enter question here..."]').set('Do you offer airport transfers?')
      find('textarea[placeholder="Write the answer..."]').set('Yes, on request.')

      click_button 'Done and Save'
    end

    expect(page).to have_current_path(edit_hotel_faq_path(hotel))

    hotel.reload
    expect(hotel.faq).to be_an(Array)
    expect(hotel.faq.first['section_name']).to eq('General')
    expect(hotel.faq.first['items'].first['question']).to eq('Do you offer airport transfers?')
  end

  it 'allows the user to save the hotel policy independently' do
    visit edit_hotel_policy_path(hotel)

    within('#hotel-policy-form') do
      click_button 'Add Policy'
      find('input[placeholder="e.g., Quiet Hours"]', wait: 5).set('Quiet Hours')
      find('textarea[placeholder="Write the policy details..."]', wait: 5).set('Quiet hours start at 10 PM.')
      click_button 'Done and Save'
    end

    expect(page).to have_current_path(edit_hotel_policy_path(hotel))
    expect(hotel.reload.policy).to eq([
      {
        'title' => 'Quiet Hours',
        'content' => 'Quiet hours start at 10 PM.'
      }
    ])
  end
end
