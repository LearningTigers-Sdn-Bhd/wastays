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

  describe 'GET /hotel/:hotel_id/rate_plans/new' do
    it 'renders the offcanvas create form' do
      get new_hotel_rate_plan_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Rate Plan")
    end
  end

  describe 'GET /hotel/:hotel_id/rate_plans/:id/edit' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate') }

    it 'renders the offcanvas edit form' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Edit Rate Plan")
      expect(response.body).to include("Promo Rate")
    end

    it 'shows a delete action when the plan has no bookings' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(response.body).to include("Delete Rate Plan")
    end

    it 'hides the delete action once the plan has a booking' do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)

      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(response.body).not_to include("Delete Rate Plan")
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
            infant_price_multiplier: 0.0,
            room_type_ids: [ room_type.id ]
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

    it 're-renders the form with errors when invalid' do
      expect {
        post hotel_rate_plans_path(hotel), params: { rate_plan: { name: '', sell_mode: 'per_room' } }
      }.not_to change(RatePlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'PATCH /hotel/:hotel_id/rate_plans/:id' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate') }

    it 'updates the rate plan' do
      patch hotel_rate_plan_path(hotel, rate_plan), params: {
        rate_plan: { extra_pax_charge: 75.0, room_type_ids: [ room_type.id ] }
      }

      expect(response).to redirect_to(hotel_rates_settings_path(hotel))
      expect(rate_plan.reload.extra_pax_charge).to eq(75.0)
      expect(rate_plan.room_types).to include(room_type)
    end
  end

  describe 'DELETE /hotel/:hotel_id/rate_plans/:id' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate') }

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
end
