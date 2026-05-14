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
    fill_in 'Email Address', with: user.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In to Portal'
  end

  it 'allows the hotel admin to update the editable settings card fields' do
    visit hotel_settings_path(hotel)

    within('section', text: 'Hotel Settings') do
      expect(page).to have_field('Standard Check-in Time', type: 'time')
      expect(page).to have_field('Standard Check-out Time', type: 'time')
      expect(page).to have_field('Hotel Status', type: 'text', disabled: true, with: 'Registered')
      expect(page).to have_field('Onboarding Stage', type: 'text', disabled: true, with: 'Building profile')
      expect(page).to have_select('Default Currency', selected: 'MYR - Malaysian Ringgit')
      expect(page).to have_content('Managed by admins in exchange rates.')
      expect(page).to have_button('Save Settings')
    end

    within('section', text: 'Tax Configuration') do
      expect(page).to have_checked_field('hotel_tourism_tax_enabled')
      expect(page).to have_field('Tourism Tax Amount (RM)')
    end

    fill_in 'Standard Check-in Time', with: '15:00'
    fill_in 'Standard Check-out Time', with: '11:00'
    select 'USD - US Dollar', from: 'Default Currency'

    click_button 'Save Settings'

    expect(page).to have_content('Settings updated successfully.')
    expect(hotel.reload.property_policy.check_in_time).to eq('15:00')
    expect(hotel.reload.property_policy.check_out_time).to eq('11:00')
    expect(hotel.reload.default_currency).to eq('USD')
  end

  it 'shows hotel status and onboarding stage as disabled text inputs' do
    visit hotel_settings_path(hotel)

    within('section', text: 'Hotel Settings') do
      expect(page).to have_field('Hotel Status', type: 'text', disabled: true, with: 'Registered')
      expect(page).to have_field('Onboarding Stage', type: 'text', disabled: true, with: 'Building profile')
    end
  end

  it 'hides tourism tax amount when tourism tax is off' do
    hotel.update!(tourism_tax_enabled: false, tourism_tax_amount: 10.0)

    visit hotel_settings_path(hotel)

    within('section', text: 'Tax Configuration') do
      expect(page).to have_unchecked_field('hotel_tourism_tax_enabled')
      expect(page).to have_field('Tourism Tax Amount (RM)', disabled: true)
    end
  end

  it 'shows validation errors when the settings card submission is invalid' do
    visit hotel_settings_path(hotel)

    fill_in 'Standard Check-in Time', with: '15:00'
    fill_in 'Standard Check-out Time', with: ''

    click_button 'Save Settings'

    within('section', text: 'Hotel Settings') do
      expect(page).to have_content('prohibited these settings from being saved')
      expect(page).to have_content("Check out time can't be blank")
      expect(find_field('Standard Check-in Time').value).to eq('15:00')
      expect(find_field('Standard Check-out Time').value).to eq('')
    end

    expect(page).to have_no_content('Settings updated successfully.')
  end

  it 'shows the AI concierge fields and saves the selected tone' do
    visit hotel_settings_path(hotel)

    within('section', text: 'AI Concierge Configuration') do
      expect(page).to have_select('Tone', selected: 'Basic')
      expect(page).to have_select('AI Provider')
      expect(page).to have_field('API Key')

      select 'Cheerful', from: 'Tone'
      select 'OpenAI', from: 'AI Provider'
      fill_in 'API Key', with: 'test-api-key'

      click_button 'Save AI Concierge Configuration'
    end

    expect(page).to have_content('Settings updated successfully.')
    hotel.reload
    expect(hotel.ai_concierge_tone).to eq('cheerful')
    expect(hotel.ai_provider_name).to eq('openai')
  end

  it 'keeps the selected hotel in the path after a superadmin saves settings' do
    superadmin = create(:user, account: account, role: 'superadmin')

    page.driver.submit :delete, logout_path, {}
    visit login_path
    fill_in 'Email Address', with: superadmin.email
    fill_in 'Password', with: 'password123'
    click_button 'Sign In to Portal'

    visit hotel_settings_path(hotel)

    fill_in 'Standard Check-in Time', with: '15:00'
    fill_in 'Standard Check-out Time', with: '11:00'
    select 'GBP - Pound Sterling', from: 'Default Currency'
    click_button 'Save Settings'

    expect(page).to have_current_path(hotel_settings_path(hotel), ignore_query: true)
    expect(page).to have_content('Settings updated successfully.')
  end
end
