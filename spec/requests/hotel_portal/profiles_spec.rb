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
  end
end
