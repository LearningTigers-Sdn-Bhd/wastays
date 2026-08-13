require 'rails_helper'

RSpec.describe 'Hotel Portal Rate Plan Age Bands', type: :system do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  # Age bands only apply to per-guest pricing, which is a property-level setting.
  let(:hotel) { create(:hotel, :per_person, account: account, status: 'setup') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }
  let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: "Per Person Plan", kind: "custom") }
  let!(:band) { create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 4, max_age: 11, price_value: 40, label: "Child") }
  # A plan with no category assignment fails validation on save, so every edit
  # in here would come back with "must include at least one room category".
  let!(:room_type) { create(:room_type, hotel: hotel, max_adults: 2, base_price: 300) }
  let!(:assignment) do
    create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan).tap do |rtrp|
      # A per-person plan must price every adult count the category seats, so
      # without these the form comes back asking for them instead of saving.
      rtrp.occupancy_prices.create!(adults: 1, price: 200)
      rtrp.occupancy_prices.create!(adults: 2, price: 300)
    end
  end

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
    visit hotel_room_types_path(hotel)

    visit edit_hotel_rate_plan_path(hotel, rate_plan, room_type_id: room_type.id)

    expect(page).to have_content('Child pricing')

    find("input[name='rate_plan[rate_plan_age_bands_attributes][0][max_age]']").set('12')
    find("input[name='rate_plan[rate_plan_age_bands_attributes][0][price_value]']").set('35')
    click_button 'Save rate plan'

    band.reload
    expect(band.max_age).to eq(12)
    expect(band.price_value.to_f).to eq(35.0)
  end

  it 'removes an age band when marked for destruction' do
    visit hotel_room_types_path(hotel)

    visit edit_hotel_rate_plan_path(hotel, rate_plan, room_type_id: room_type.id)

    find("input[name='rate_plan[rate_plan_age_bands_attributes][0][_destroy]']", visible: false).set('1')
    click_button 'Save rate plan'

    expect(RatePlanAgeBand.exists?(band.id)).to be false
  end
end
