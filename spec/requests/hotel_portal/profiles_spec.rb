# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'HotelPortal::Profiles', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'approved') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner') }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |p| p.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe 'GET /hotel/:hotel_id/profile/edit' do
    it 'renders the canonical hotel details page' do
      get edit_hotel_profile_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.css("h1").map { |heading| heading.text.squish }).to eq([ "Hotel Details" ])
      expect(response.body).to include(%(id="hotel-profile-section"))
      expect(response.body).to include(%(data-testid="settings-tabs"))
    end
  end

  describe 'PATCH /hotel/profile' do
    it 'updates hotel profile including star rating and google map link' do
      patch hotel_profile_path(hotel), params: {
        hotel: {
          name: 'Updated Hotel Name',
          star_rating: '5',
          google_map_link: 'https://www.google.com/maps/place/Updated+Hotel'
        }
      }

      hotel.reload
      expect(response).to redirect_to(edit_hotel_profile_path(hotel))
      follow_redirect!
      expect(response.body).to include('Hotel profile updated successfully.')

      expect(hotel.name).to eq('Updated Hotel Name')
      expect(hotel.star_rating).to eq(5)
      expect(hotel.google_map_link).to eq('https://www.google.com/maps/place/Updated+Hotel')
    end

    it "renders the canonical hotel details page when profile update is invalid" do
      patch hotel_profile_path(hotel), params: {
        hotel: {
          name: "",
          city: hotel.city,
          country: hotel.country
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(id="hotel-profile-section"))
      expect(response.body).to include(%(data-testid="settings-tabs"))
    end
  end
end
