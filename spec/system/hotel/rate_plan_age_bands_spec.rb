require 'rails_helper'

RSpec.describe 'Hotel Portal Rate Plan Age Bands', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  # Age bands only apply to per-guest pricing, which is a property-level setting.
  let(:hotel) { create(:hotel, :per_person, account: account, status: 'registered') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }
  let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: "Per Person Plan", kind: "custom") }
  let!(:band) { create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 4, max_age: 11, price_value: 40, label: "Child") }

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

  it 'lets the hotelier edit an existing age band and persists the change' do
    visit hotel_settings_path(hotel, tab: 'rates')

    first(:link, 'Manage').click

    expect(page).to have_content('Child age groups')

    find("input[name='rate_plan[rate_plan_age_bands_attributes][0][max_age]']").set('12')
    find("input[name='rate_plan[rate_plan_age_bands_attributes][0][price_value]']").set('35')
    click_button 'Save changes'

    expect(page).to have_content("updated successfully")
    band.reload
    expect(band.max_age).to eq(12)
    expect(band.price_value.to_f).to eq(35.0)
  end

  it 'removes an age band when marked for destruction' do
    visit hotel_settings_path(hotel, tab: 'rates')

    first(:link, 'Manage').click

    find("input[name='rate_plan[rate_plan_age_bands_attributes][0][_destroy]']", visible: false).set('1')
    click_button 'Save changes'

    expect(page).to have_content("updated successfully")
    expect(RatePlanAgeBand.exists?(band.id)).to be false
  end
end
