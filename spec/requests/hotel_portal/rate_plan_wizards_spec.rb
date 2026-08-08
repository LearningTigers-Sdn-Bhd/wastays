require 'rails_helper'

RSpec.describe 'HotelPortal::RatePlanWizards', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'live') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }
  let!(:twin) { create(:room_type, hotel: hotel, name: 'Deluxe twin', max_adults: 2, base_price: 320) }
  let!(:suite) { create(:room_type, hotel: hotel, name: 'Beachfront suite', max_adults: 4, base_price: 750) }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def step_path(step) = hotel_rate_plan_wizard_step_path(hotel, step)
  def room_step(room_type) = HotelPortal::RatePlanWizard.room_step(room_type.id)

  def submit_details(room_types:, **overrides)
    patch step_path('details'), params: {
      rate_plan: { name: 'Non-refundable rate', room_type_ids: room_types.map { |rt| rt.id.to_s } }.merge(overrides)
    }
  end

  describe 'GET start' do
    it 'clears any previous draft and opens the details step' do
      get hotel_start_rate_plan_wizard_path(hotel)

      expect(response).to redirect_to(step_path('details'))
      follow_redirect!
      expect(response.body).to include('What this plan is')
      expect(response.body).to include('Deluxe twin')
    end

    it 'renders into the settings action sheet as a full bottom sheet' do
      get hotel_start_rate_plan_wizard_path(hotel)
      follow_redirect!

      dialog = Nokogiri::HTML(response.body).at_css('turbo-frame#settings_action_sheet dialog#rate-plan-wizard-sheet')
      expect(dialog).to be_present
      expect(dialog[:class]).to include('bottom-0')
      expect(response.body).to include('Step 1 of')
    end

    it 'binds the footer submit to the form in the sheet body' do
      get hotel_start_rate_plan_wizard_path(hotel)
      follow_redirect!

      page = Nokogiri::HTML(response.body)
      # The footer sits outside the <form>, so the buttons only work through the
      # HTML form attribute pointing at an id that actually exists.
      submit = page.at_css('button[type="submit"][form="rate-plan-wizard-details"]')
      expect(submit).to be_present
      expect(page.at_css('form#rate-plan-wizard-details')).to be_present
    end
  end

  describe 'step progression' do
    it 'creates one pricing step per selected room category' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin, suite ])

      expect(response).to redirect_to(step_path(room_step(twin)))
      follow_redirect!
      expect(response.body).to include('Deluxe twin')
      expect(response.body).to include('2 adults max')
    end

    it 'refuses a draft with no room categories' do
      get hotel_start_rate_plan_wizard_path(hotel)
      patch step_path('details'), params: { rate_plan: { name: 'Empty plan', room_type_ids: [ '' ] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('must include at least one room category')
    end

    it 'sends a deep link past an unanswered step back to the gap' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin, suite ])

      get step_path('review')

      expect(response).to redirect_to(step_path(room_step(twin)))
    end

    it 'drops answers for a category that is unticked before it is priced' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin, suite ])
      patch step_path(room_step(twin)), params: { room_pricing: { rate_mode: 'manual', default_rate: '300' } }

      submit_details(room_types: [ suite ])
      get step_path(room_step(twin))

      expect(response).to redirect_to(step_path(room_step(suite)))
    end
  end

  context 'when the property sells per room' do
    before { hotel.update!(sell_mode: 'per_room') }

    it 'stores a typed rate on the assignment and creates the plan' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin ], base_occupancy: '2', extra_pax_charge: '75')
      patch step_path(room_step(twin)), params: { room_pricing: { rate_mode: 'manual', default_rate: '300' } }

      expect(response).to redirect_to(step_path('review'))
      follow_redirect!
      expect(response.body).to include('Base occupancy 2')

      expect { post hotel_complete_rate_plan_wizard_path(hotel) }.to change(RatePlan, :count).by(1)

      plan = RatePlan.order(:id).last
      assignment = plan.room_type_rate_plans.sole
      expect(plan.extra_pax_charge).to eq(75)
      expect(assignment.pricing_mode).to eq('fixed')
      expect(assignment.pricing_value).to eq(300)
      expect(assignment.occupancy_prices).to be_empty
    end

    it 'keeps a derived plan following the standard rate rather than materialising it' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin ])
      patch step_path(room_step(twin)), params: {
        room_pricing: { rate_mode: 'derived', derive_mode: 'multiplier', derive_value: '-10' }
      }
      post hotel_complete_rate_plan_wizard_path(hotel)

      assignment = RatePlan.order(:id).last.room_type_rate_plans.sole
      expect(assignment.pricing_mode).to eq('multiplier')
      expect(assignment.pricing_value).to eq(-10)
    end

    it 'does not offer Auto, which has no adult count to step through' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin ])
      get step_path(room_step(twin))

      expect(response.body).to include('Manual')
      expect(response.body).to include('Derived')
      expect(response.body).not_to include('Start from a rate you set')
    end
  end

  context 'when the property sells per person' do
    before { hotel.update!(sell_mode: 'per_person') }

    it 'prices each category to its own capacity, not the property maximum' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin, suite ], child_price_multiplier: '0.5')

      get step_path(room_step(twin))
      expect(response.body).to include('room_pricing[prices][2]')
      expect(response.body).not_to include('room_pricing[prices][3]')

      patch step_path(room_step(twin)), params: {
        room_pricing: { rate_mode: 'manual', prices: { '1' => '220', '2' => '320' } }
      }
      get step_path(room_step(suite))
      expect(response.body).to include('room_pricing[prices][4]')
    end

    it 'renders an age band template the add button can actually clone' do
      get hotel_start_rate_plan_wizard_path(hotel)
      follow_redirect!

      expect(response.body).to include('Add age group')
      expect(response.body).to include('rate_plan[rate_plan_age_bands_attributes][NEW_RECORD][min_age]')
    end

    it 'does not ask for a single supplement, which the one-adult price already is' do
      get hotel_start_rate_plan_wizard_path(hotel)
      follow_redirect!

      expect(response.body).not_to include('rate_plan[single_supplement]')
    end

    it 'refuses a partial matrix, naming the counts that are missing' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ suite ])
      patch step_path(room_step(suite)), params: {
        room_pricing: { rate_mode: 'manual', prices: { '1' => '750', '2' => '930' } }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Enter a price for 3 adults and 4 adults')
    end

    it 'materialises a complete matrix from the Auto ladder' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ suite ], child_price_multiplier: '0.5')
      patch step_path(room_step(suite)), params: {
        room_pricing: {
          rate_mode: 'auto', default_rate: '750', primary_occupancy: '2',
          increase_by: '180', decrease_by: '100'
        }
      }
      post hotel_complete_rate_plan_wizard_path(hotel)

      assignment = RatePlan.order(:id).last.room_type_rate_plans.sole
      expect(assignment.pricing_mode).to eq('fixed')
      expect(assignment.occupancy_prices.order(:adults).pluck(:adults, :price))
        .to eq([ [ 1, 650 ], [ 2, 750 ], [ 3, 930 ], [ 4, 1110 ] ])
    end

    it 'anchors a derived ladder on the category standard rate' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin ], child_price_multiplier: '0.5')
      patch step_path(room_step(twin)), params: {
        room_pricing: {
          rate_mode: 'derived', derive_mode: 'multiplier', derive_value: '-10',
          primary_occupancy: '2', decrease_by: '100'
        }
      }
      post hotel_complete_rate_plan_wizard_path(hotel)

      assignment = RatePlan.order(:id).last.room_type_rate_plans.sole
      expect(assignment.occupancy_prices.order(:adults).pluck(:adults, :price))
        .to eq([ [ 1, 188 ], [ 2, 288 ] ])
    end

    it 'saves the plan-level child age bands from the details step' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(
        room_types: [ twin ],
        child_price_multiplier: '0.5',
        rate_plan_age_bands_attributes: {
          '0' => { label: 'Infant', min_age: '0', max_age: '2', pricing_mode: 'amount', price_value: '0' }
        }
      )
      patch step_path(room_step(twin)), params: {
        room_pricing: { rate_mode: 'manual', prices: { '1' => '220', '2' => '320' } }
      }
      post hotel_complete_rate_plan_wizard_path(hotel)

      plan = RatePlan.order(:id).last
      expect(plan.rate_plan_age_bands.pluck(:label, :min_age, :max_age)).to eq([ [ 'Infant', 0, 2 ] ])
      expect(plan.sell_mode).to eq('per_person')
    end
  end

  describe 'apply to all rooms' do
    before { hotel.update!(sell_mode: 'per_room') }

    it 'copies one answer onto every remaining category' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin, suite ])
      patch step_path(room_step(twin)), params: {
        room_pricing: { rate_mode: 'manual', default_rate: '300' }, apply_to_all: '1'
      }
      post hotel_complete_rate_plan_wizard_path(hotel)

      expect(RatePlan.order(:id).last.room_type_rate_plans.pluck(:pricing_value)).to all(eq(300))
    end
  end

  describe 'DELETE discard' do
    it 'drops the draft without writing anything' do
      get hotel_start_rate_plan_wizard_path(hotel)
      submit_details(room_types: [ twin ])

      expect { delete hotel_rate_plan_wizard_path(hotel) }.not_to change(RatePlan, :count)
      expect(response).to redirect_to(hotel_rates_settings_path(hotel))

      get step_path('review')
      expect(response).to redirect_to(step_path('details'))
    end
  end
end
