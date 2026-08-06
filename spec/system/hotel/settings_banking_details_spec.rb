require 'rails_helper'

RSpec.describe 'Hotel Settings Banking Details', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }

  before do
    driven_by(:rack_test)

    Permission.find_or_create_by!(slug: 'manage_account') { |permission| permission.name = 'Manage Account' }
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_account'))
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    sign_in_through_ui(user)
  end

  it 'allows the user to add banking details from the settings page' do
    visit hotel_banking_details_settings_path(hotel)

    fill_in 'account_banking_detail_attributes_account_holder_name', with: 'Syarikat Maju Jaya Sdn Bhd'
    select 'Maybank', from: 'account_banking_detail_attributes_bank_name'
    fill_in 'account_banking_detail_attributes_account_number', with: '5142 1234 5678'

    click_button 'Save Banking Details'

    expect(page).to have_content('Settings updated successfully.')

    banking_detail = account.reload.banking_detail
    expect(banking_detail.account_holder_name).to eq('Syarikat Maju Jaya Sdn Bhd')
    expect(banking_detail.bank_name).to eq('Maybank')
    expect(banking_detail.account_number).to eq('5142 1234 5678')
    expect(hotel.reload.status).to eq('approved')
  end

  it 'saves banking details independently of the display-only settings card' do
    visit hotel_banking_details_settings_path(hotel)

    fill_in 'account_banking_detail_attributes_account_holder_name', with: 'Kejayaan Hotel Sdn Bhd'
    select 'CIMB', from: 'account_banking_detail_attributes_bank_name'
    fill_in 'account_banking_detail_attributes_account_number', with: '1234 5678 9012'

    click_button 'Save Banking Details'

    expect(page).to have_content('Settings updated successfully.')
    expect(account.reload.banking_detail.account_holder_name).to eq('Kejayaan Hotel Sdn Bhd')
    expect(hotel.reload.status).to eq('approved')
  end

  it 'shows validation errors when banking details are invalid' do
    visit hotel_banking_details_settings_path(hotel)

    fill_in 'account_banking_detail_attributes_account_holder_name', with: ''
    select 'Search and select a bank', from: 'account_banking_detail_attributes_bank_name'
    fill_in 'account_banking_detail_attributes_account_number', with: '1234/5678'

    click_button 'Save Banking Details'

    expect(page).to have_content('3 errors prevented these settings from being saved')
    expect(page).to have_content("Banking detail account holder name can't be blank")
    expect(page).to have_content("Banking detail bank name can't be blank")
    expect(page).to have_content('Banking detail account number is invalid')
  end
end
