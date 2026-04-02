require 'rails_helper'

RSpec.describe 'Hotel Settings Card', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) do
    create(:hotel, account: account, status: 'registered', tourism_tax_enabled: true, tourism_tax_amount: 10.0)
  end
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }

  before do
    driven_by(:rack_test)

    Permission.find_or_create_by!(slug: 'manage_account') { |permission| permission.name = 'Manage Account' }
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_account'))
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in 'Email address', with: user.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In'
  end

  it 'allows the hotel admin to update the editable settings card fields' do
    visit hotel_settings_path

    within all('.card').first do
      expect(page).to have_field('Standard Check-in Time', type: 'time')
      expect(page).to have_field('Standard Check-out Time', type: 'time')
      expect(page).to have_field('Hotel Status', type: 'text', disabled: true, with: 'Registered')
      expect(page).to have_field('Onboarding Stage', type: 'text', disabled: true, with: 'Building profile')
      expect(page).to have_field('Default Currency', disabled: true, with: 'MYR')
      expect(page).to have_field('USD Conversion Rate')
      expect(page).to have_checked_field('hotel_tourism_tax_enabled')
      expect(page).to have_field('Tourism Tax Amount')
      expect(page).to have_button('Save Settings')
    end

    fill_in 'Standard Check-in Time', with: '15:00'
    fill_in 'Standard Check-out Time', with: '11:00'
    fill_in 'USD Conversion Rate', with: '4.25'
    check 'hotel_tourism_tax_enabled'
    fill_in 'Tourism Tax Amount', with: '10.00'

    click_button 'Save Settings'

    expect(page).to have_content('Settings updated successfully.')
    expect(hotel.reload.property_policy.check_in_time).to eq('15:00')
    expect(hotel.reload.property_policy.check_out_time).to eq('11:00')
    expect(hotel.reload.default_currency).to eq('MYR')
    expect(hotel.reload.usd_conversion_rate).to eq(4.25)
    expect(hotel.reload.tourism_tax_enabled?).to be(true)
  end

  it 'shows hotel status and onboarding stage as disabled text inputs' do
    visit hotel_settings_path

    within all('.card').first do
      expect(page).to have_field('Hotel Status', type: 'text', disabled: true, with: 'Registered')
      expect(page).to have_field('Onboarding Stage', type: 'text', disabled: true, with: 'Building profile')
    end
  end

  it 'hides tourism tax amount when tourism tax is off' do
    hotel.update!(tourism_tax_enabled: false, tourism_tax_amount: 10.0)

    visit hotel_settings_path

    within all('.card').first do
      expect(page).to have_unchecked_field('hotel_tourism_tax_enabled')
      expect(page).to have_field('Tourism Tax Amount', disabled: true)
    end
  end

  it 'shows validation errors when the settings card submission is invalid' do
    visit hotel_settings_path

    fill_in 'Standard Check-in Time', with: '15:00'
    fill_in 'Standard Check-out Time', with: ''

    click_button 'Save Settings'

    within all('.card').first do
      expect(page).to have_content('prohibited these settings from being saved')
      expect(page).to have_content("Check out time can't be blank")
      expect(find_field('Standard Check-in Time').value).to eq('15:00')
      expect(find_field('Standard Check-out Time').value).to eq('')
    end

    expect(page).to have_no_content('Settings updated successfully.')
  end
end
