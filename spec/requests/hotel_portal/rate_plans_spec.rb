require 'rails_helper'

RSpec.describe 'HotelPortal::RatePlans', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'live', allow_pax_pricing: true) }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }
  let!(:room_type) { create(:room_type, hotel: hotel) }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def delete_action_labels(body)
    Nokogiri::HTML(body).css('a[data-turbo-method="delete"]').map { |link| link.text.strip }
  end

  describe 'GET /hotel/:hotel_id/rate_plans/new' do
    it 'renders the create form in a sheet' do
      get new_hotel_rate_plan_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New rate plan")
      expect(Nokogiri::HTML(response.body).at_css('turbo-frame#settings_action_sheet dialog')).to be_present
    end
  end

  describe 'GET /hotel/:hotel_id/rate_plans/:id/edit' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate', kind: 'custom') }

    it 'renders the edit form in a sheet' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit rate plan")
      expect(Nokogiri::HTML(response.body).at_css('turbo-frame#settings_action_sheet dialog')).to be_present
      expect(response.body).to include("Promo Rate")
    end

    it 'offers both sell modes when the hotel allows pax pricing but is not pax-only' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      select = Nokogiri::HTML(response.body).at_css('select#rate_plan_sell_mode')
      option_values = select.css('option').map { |o| o['value'] }.reject(&:blank?)
      expect(option_values).to contain_exactly('per_room', 'per_person')
    end

    it 'offers only Per Person when the hotel is pax-pricing only' do
      hotel.update!(pax_pricing_only: true)
      per_person_plan = create(:rate_plan, hotel: hotel, name: 'Family Plan', kind: 'custom', sell_mode: 'per_person')

      get edit_hotel_rate_plan_path(hotel, per_person_plan)

      select = Nokogiri::HTML(response.body).at_css('select#rate_plan_sell_mode')
      option_values = select.css('option').map { |o| o['value'] }.reject(&:blank?)
      expect(option_values).to contain_exactly('per_person')
    end

    it 'offers only Per Room when the hotel does not allow pax pricing' do
      hotel.update!(allow_pax_pricing: false)

      get edit_hotel_rate_plan_path(hotel, rate_plan)

      select = Nokogiri::HTML(response.body).at_css('select#rate_plan_sell_mode')
      option_values = select.css('option').map { |o| o['value'] }.reject(&:blank?)
      expect(option_values).to contain_exactly('per_room')
    end

    it 'shows a delete action when the plan has no bookings' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(delete_action_labels(response.body)).to include("Delete")
    end

    it 'hides the delete action once the plan has a booking' do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)

      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(delete_action_labels(response.body)).to be_empty
    end

    it 'shows per-room-type pricing mode controls, pre-filled from existing derived pricing' do
      create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "multiplier", pricing_value: -15)

      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(response.body).to include("% of standard rate")
      expect(response.body).to include("rate_plan[room_type_pricing][#{room_type.id}][pricing_mode]")
      expect(response.body).to include('value="-15.0"')
    end

    it 'wires up a live price preview per room type, anchored to that room type\'s own Standard Rate' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(response.body).to include('data-controller="room-type-pricing-row"')
      expect(response.body).to include("data-room-type-pricing-row-anchor-price-value=\"#{room_type.base_price}\"")
      expect(response.body).to include('data-room-type-pricing-row-target="preview"')
    end

    it 'wires up a live price preview for each age band, using the room type Standard Rate and a mode choice' do
      per_person_plan = create(:rate_plan, hotel: hotel, name: 'Family Plan', kind: 'custom', sell_mode: 'per_person', currency: 'MYR')
      create(:rate_plan_age_band, rate_plan: per_person_plan, min_age: 4, max_age: 11, price_value: 40, label: 'Child')

      get edit_hotel_rate_plan_path(hotel, per_person_plan)

      expect(response.body).to include('data-controller="rate-plan-age-bands age-band-price-preview"')
      expect(response.body).to include('data-age-band-price-preview-currency-value="MYR"')
      expect(response.body).to include('data-age-band-price-preview-target="roomTypeField"')
      expect(response.body).to include('data-role="price-preview"')
      expect(response.body).to include('Fixed price per child')
    end

    it 'shows the prominent empty-state add button when there are no age groups yet' do
      per_person_plan = create(:rate_plan, hotel: hotel, name: 'Family Plan', kind: 'custom', sell_mode: 'per_person', currency: 'MYR')

      get edit_hotel_rate_plan_path(hotel, per_person_plan)

      empty_state = Nokogiri::HTML(response.body).at_css('[data-rate-plan-age-bands-target="emptyState"]')
      expect(empty_state.text).to include('Add your first age group')
      expect(empty_state["class"]).not_to include("hidden")
    end

    it 'hides the empty-state add button once age groups already exist' do
      per_person_plan = create(:rate_plan, hotel: hotel, name: 'Family Plan', kind: 'custom', sell_mode: 'per_person', currency: 'MYR')
      create(:rate_plan_age_band, rate_plan: per_person_plan, min_age: 4, max_age: 11, price_value: 40, label: 'Child')

      get edit_hotel_rate_plan_path(hotel, per_person_plan)

      empty_state = Nokogiri::HTML(response.body).at_css('[data-rate-plan-age-bands-target="emptyState"]')
      expect(empty_state["class"]).to include("hidden")
    end
  end

  describe 'POST /hotel/:hotel_id/rate_plans' do
    it 'creates a new rate plan and links it to selected room types' do
      expect {
        post hotel_rate_plans_path(hotel), params: {
          rate_plan: {
            name: 'Flexible Breakfast Rate',
            sell_mode: 'per_person',
            base_occupancy: 2,
            extra_pax_charge: 50.0,
            single_supplement: 30.0,
            child_price_multiplier: 0.5,
            room_type_pricing: { room_type.id.to_s => { enabled: "1", pricing_mode: "fixed" } }
          }
        }
      }.to change(RatePlan, :count).by(1)

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include("created successfully")

      rate_plan = RatePlan.last
      expect(rate_plan.name).to eq('Flexible Breakfast Rate')
      expect(rate_plan.sell_mode).to eq('per_person')
      expect(rate_plan.room_types).to include(room_type)
    end

    it 'creates a room type rate plan with derived multiplier pricing' do
      post hotel_rate_plans_path(hotel), params: {
        rate_plan: {
          name: 'Non-Refundable',
          sell_mode: 'per_room',
          room_type_pricing: { room_type.id.to_s => { enabled: "1", pricing_mode: "multiplier", pricing_value: "-10" } }
        }
      }

      rate_plan = RatePlan.last
      rtrp = rate_plan.room_type_rate_plans.find_by(room_type: room_type)
      expect(rtrp.pricing_mode).to eq('multiplier')
      expect(rtrp.pricing_value.to_f).to eq(-10.0)
    end

    it 're-renders with errors when a derived room type row is missing its pricing value' do
      expect {
        post hotel_rate_plans_path(hotel), params: {
          rate_plan: {
            name: 'Non-Refundable',
            sell_mode: 'per_room',
            room_type_pricing: { room_type.id.to_s => { enabled: "1", pricing_mode: "multiplier", pricing_value: "" } }
          }
        }
      }.not_to change(RatePlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 're-renders the form with errors when invalid' do
      expect {
        post hotel_rate_plans_path(hotel), params: { rate_plan: { name: '', sell_mode: 'per_room' } }
      }.not_to change(RatePlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'PATCH /hotel/:hotel_id/rate_plans/:id' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate', kind: 'custom') }

    it 'updates the rate plan' do
      patch hotel_rate_plan_path(hotel, rate_plan), params: {
        rate_plan: { extra_pax_charge: 75.0, room_type_pricing: { room_type.id.to_s => { enabled: "1", pricing_mode: "fixed" } } }
      }

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(rate_plan.reload.extra_pax_charge).to eq(75.0)
      expect(rate_plan.room_types).to include(room_type)
    end

    it 'removes a room type when unchecked' do
      create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: 'fixed')

      patch hotel_rate_plan_path(hotel, rate_plan), params: {
        rate_plan: { room_type_pricing: { room_type.id.to_s => { enabled: "0" } } }
      }

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(rate_plan.reload.room_types).not_to include(room_type)
    end

    it 'refuses to reassign a standard plan, even if room_type_pricing is submitted' do
      other_room_type = create(:room_type, hotel: hotel, name: 'Suite')
      standard = room_type.rate_plans.find_by(kind: 'standard')

      patch hotel_rate_plan_path(hotel, standard), params: {
        rate_plan: { room_type_pricing: { other_room_type.id.to_s => { enabled: "1", pricing_mode: "fixed" } } }
      }

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(standard.reload.room_types).to contain_exactly(room_type)
    end

    it 'refuses to unassign a standard plan from its own room category' do
      standard = room_type.rate_plans.find_by(kind: 'standard')

      patch hotel_rate_plan_path(hotel, standard), params: {
        rate_plan: { room_type_pricing: { room_type.id.to_s => { enabled: "0" } } }
      }

      expect(standard.reload.room_types).to contain_exactly(room_type)
    end

    # An unchecked PanelsUI::Checkbox submits no `enabled` key at all — the row
    # only reaches the server because its pricing_mode field always submits.
    it 'removes a room type when the enabled key is omitted entirely' do
      create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: 'fixed')

      patch hotel_rate_plan_path(hotel, rate_plan), params: {
        rate_plan: { room_type_pricing: { room_type.id.to_s => { pricing_mode: "fixed" } } }
      }

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(rate_plan.reload.room_types).not_to include(room_type)
    end
  end

  describe 'DELETE /hotel/:hotel_id/rate_plans/:id' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate', kind: 'custom') }

    it 'deletes custom rate plan' do
      expect {
        delete hotel_rate_plan_path(hotel, rate_plan)
      }.to change(RatePlan, :count).by(-1)

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
    end

    it 'prevents deleting standard rate plan' do
      standard_rate = hotel.rate_plans.find_by(name: 'Standard Rate') || create(:rate_plan, hotel: hotel, name: 'Standard Rate')

      expect {
        delete hotel_rate_plan_path(hotel, standard_rate)
      }.not_to change(RatePlan, :count)

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(flash[:alert]).to include("cannot be deleted")
    end

    it 'prevents deleting a rate plan that has existing bookings' do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)

      expect {
        delete hotel_rate_plan_path(hotel, rate_plan)
      }.not_to change(RatePlan, :count)

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(flash[:alert]).to include("cannot be deleted")
    end
  end

  describe 'PATCH /hotel/:hotel_id/rate_plans/:id/archive' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate', kind: 'custom') }

    it 'archives a custom rate plan, including one with existing bookings' do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)

      patch archive_hotel_rate_plan_path(hotel, rate_plan)

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(rate_plan.reload.archived?).to be true
    end

    it 'prevents archiving the standard rate plan' do
      standard_rate = hotel.rate_plans.find_by(name: 'Standard Rate') || create(:rate_plan, hotel: hotel, name: 'Standard Rate')

      patch archive_hotel_rate_plan_path(hotel, standard_rate)

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(flash[:alert]).to include("cannot be archived")
      expect(standard_rate.reload.archived?).to be false
    end

    it 'excludes an archived rate plan from availability search results' do
      create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan)
      rate_plan.archive!

      service = BookingEngine::AvailabilityService.new(check_in: Date.tomorrow, check_out: Date.tomorrow + 2.days, adults: 2)
      options = service.send(:candidate_rate_plans_for, room_type)

      expect(options).not_to include(rate_plan)
    end
  end

  describe 'PATCH /hotel/:hotel_id/rate_plans/:id/unarchive' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate', kind: 'custom', archived_at: Time.current) }

    it 'restores an archived rate plan' do
      patch unarchive_hotel_rate_plan_path(hotel, rate_plan)

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(rate_plan.reload.archived?).to be false
    end
  end
end
