require 'rails_helper'

RSpec.describe 'HotelPortal::NearbyAttractions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'live') }
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
      attraction = create(:nearby_attraction, hotel: hotel, name: "Batu Caves")

      get hotel_nearby_attractions_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.css("h1").map { |heading| heading.text.squish }).to eq([ "Property Details Settings" ])
      expect(document.at_css("h2#nearby-attractions-heading").text.squish).to eq("Nearby Attractions")
      expect(document.css(".panel-button").map { |button| button.text.squish }).to include("Create")
      expect(document.at_css(".panel-table caption.sr-only").text.squish).to eq("Nearby attractions")
      expect(document.css(".panel-card").map { |card| card.text.squish }).to include(a_string_including(attraction.name))
      expect(document.css("[id$='nearby-attraction-#{attraction.id}-actions'].dropdown-menu-root").count).to eq(2)
      expect(document.css("button[data-turbo-confirm-tone='destructive']").count).to eq(2)
      expect(document.at_css("body").text).not_to include("Total Attractions")
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

    it 'responds with a turbo stream that refreshes the list and closes the sheet' do
      post hotel_nearby_attractions_path(hotel), as: :turbo_stream, params: {
        nearby_attraction: {
          name: 'Batu Caves',
          city: 'Kuala Lumpur',
          country: 'Malaysia'
        }
      }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('action="replace" target="nearby_attractions_list"')
      expect(response.body).to include('action="update" target="nearby_attraction_form"')
      expect(response.body).to include('action="append" target="toast-viewport"')
      expect(response.body).to include('Nearby attraction created successfully.')
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
      expect(response.body).to include('turbo-frame id="nearby_attraction_form"')
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

    it 'responds with a turbo stream that refreshes the list and closes the sheet' do
      nearby_attraction = create(:nearby_attraction, hotel: hotel, name: 'KL Tower')

      patch hotel_nearby_attraction_path(hotel, nearby_attraction), as: :turbo_stream, params: {
        nearby_attraction: {
          name: 'Petronas Twin Towers',
          city: 'Kuala Lumpur',
          country: 'Malaysia'
        }
      }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('action="replace" target="nearby_attractions_list"')
      expect(response.body).to include('action="update" target="nearby_attraction_form"')
      expect(response.body).to include('Nearby attraction updated successfully.')
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
