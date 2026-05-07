require 'rails_helper'

RSpec.describe 'HotelPortal::NearbyAttractions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe 'GET /hotel/:hotel_id/nearby_attractions' do
    it 'renders the nearby attractions index' do
      get hotel_nearby_attractions_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Nearby Attractions')
      expect(response.body).to include('Add Nearby Attraction')
    end
  end

  describe 'POST /hotel/:hotel_id/nearby_attractions' do
    it 'creates a nearby attraction' do
      expect {
        post hotel_nearby_attractions_path(hotel), params: {
          nearby_attraction: {
            name: 'Batu Caves',
            description: 'A limestone hill with caves and temples.',
            address: 'Gombak, 68100 Batu Caves',
            city: 'Kuala Lumpur',
            country: 'Malaysia'
          }
        }
      }.to change(NearbyAttraction, :count).by(1)

      expect(response).to redirect_to(hotel_nearby_attractions_path(hotel))
      expect(NearbyAttraction.last.name).to eq('Batu Caves')
    end

    it 'rejects invalid nearby attractions' do
      post hotel_nearby_attractions_path(hotel), params: {
        nearby_attraction: {
          name: '',
          city: '',
          country: ''
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Add Nearby Attraction')
    end
  end

  describe 'PATCH /hotel/:hotel_id/nearby_attractions/:id' do
    it 'updates a nearby attraction' do
      nearby_attraction = create(:nearby_attraction, hotel: hotel, name: 'KL Tower')

      patch hotel_nearby_attraction_path(hotel, nearby_attraction), params: {
        nearby_attraction: {
          name: 'Petronas Twin Towers',
          city: 'Kuala Lumpur',
          country: 'Malaysia'
        }
      }

      expect(response).to redirect_to(hotel_nearby_attractions_path(hotel))
      expect(nearby_attraction.reload.name).to eq('Petronas Twin Towers')
    end
  end

  describe 'DELETE /hotel/:hotel_id/nearby_attractions/:id' do
    it 'deletes a nearby attraction' do
      nearby_attraction = create(:nearby_attraction, hotel: hotel)

      expect {
        delete hotel_nearby_attraction_path(hotel, nearby_attraction)
      }.to change(NearbyAttraction, :count).by(-1)

      expect(response).to redirect_to(hotel_nearby_attractions_path(hotel))
    end
  end
end
