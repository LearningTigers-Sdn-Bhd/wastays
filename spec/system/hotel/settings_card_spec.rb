require 'rails_helper'

RSpec.describe 'Hotel Settings Card', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) do
    create(:hotel, account: account, status: 'setup', tourism_tax_enabled: true, tourism_tax_amount: 10.0)
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

    sign_in_through_ui(user)
  end

  it 'allows the hotel admin to update the editable settings card fields' do
    visit hotel_general_settings_path(hotel)

    within("form[action='#{hotel_general_settings_path(hotel)}']") do
      expect(page).to have_css('.panel-metric-card__label', text: 'Hotel Status')
      expect(page).to have_css('.panel-metric-card__value', text: 'Setup')
      expect(page).to have_css('.panel-metric-card__label', text: 'Onboarding Stage')
      expect(page).to have_css('.panel-metric-card__value', text: 'Building profile')
      expect(page).to have_select('Default Currency', selected: 'MYR - Malaysian Ringgit')
      expect(page).to have_button('Save Settings')
    end

    visit hotel_general_settings_path(hotel)

    find('#hotel_property_policy_attributes_check_in_time', visible: false).set('15:00')
    find('#hotel_property_policy_attributes_check_out_time', visible: false).set('11:00')
    select 'USD - US Dollar', from: 'Default Currency'

    click_button 'Save Settings'

    expect(page).to have_content('Settings updated successfully.')
    expect(hotel.reload.property_policy.check_in_time).to eq('15:00')
    expect(hotel.reload.property_policy.check_out_time).to eq('11:00')
    expect(hotel.reload.default_currency).to eq('USD')
  end

  it 'shows hotel status and onboarding stage as metric cards' do
    visit hotel_general_settings_path(hotel)

    within('section', text: 'General Setup') do
      expect(page).to have_css('.panel-metric-card__label', text: 'Hotel Status')
      expect(page).to have_css('.panel-metric-card__value', text: 'Setup')
      expect(page).to have_css('.panel-metric-card__label', text: 'Onboarding Stage')
      expect(page).to have_css('.panel-metric-card__value', text: 'Building profile')
      expect(page).to have_no_field('Hotel Status', type: 'text')
      expect(page).to have_no_field('Onboarding Stage', type: 'text')
    end
  end

  it 'keeps the tourism tax amount visible while the tax is switched off' do
    hotel.update!(tourism_tax_enabled: false, tourism_tax_amount: 10.0)

    visit hotel_taxes_fees_path(hotel)

    within('#tax-registry-row-tourism_tax') do
      expect(page).to have_content('Tourism Tax (TTx)')
      expect(page).to have_content('RM 10.00 / room / night')
      expect(page).to have_field(type: 'checkbox', checked: false, visible: :all)
    end
  end

  it 'shows validation errors when the settings card submission is invalid' do
    visit hotel_general_settings_path(hotel)

    find('#hotel_property_policy_attributes_check_in_time', visible: false).set('15:00')
    find('#hotel_property_policy_attributes_check_out_time', visible: false).set('')

    click_button 'Save Settings'

    within("form[action='#{hotel_general_settings_path(hotel)}']") do
      expect(page).to have_content('prevented these settings from being saved')
      expect(page).to have_content("Check out time can't be blank")
      expect(find('#hotel_property_policy_attributes_check_in_time', visible: false).value).to eq('15:00')
      expect(find('#hotel_property_policy_attributes_check_out_time', visible: false).value).to eq('')
    end

    expect(page).to have_no_content('Settings updated successfully.')
  end

  it 'shows the AI concierge fields and saves the selected tone' do
    visit hotel_ai_concierge_settings_path(hotel)

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
    sign_in_through_ui(superadmin)

    visit hotel_general_settings_path(hotel)

    find('#hotel_property_policy_attributes_check_in_time', visible: false).set('15:00')
    find('#hotel_property_policy_attributes_check_out_time', visible: false).set('11:00')
    select 'GBP - Pound Sterling', from: 'Default Currency'
    click_button 'Save Settings'

    expect(page).to have_current_path(hotel_general_settings_path(hotel), ignore_query: true)
    expect(page).to have_content('Settings updated successfully.')
  end
end
