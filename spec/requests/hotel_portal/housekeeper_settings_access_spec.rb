require 'rails_helper'

RSpec.describe 'HotelPortal::Settings Housekeeper Access', type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:housekeeper_role) { create(:role, account: account, slug: 'housekeeper', name: 'Housekeeper') }
  let(:housekeeper) { create(:user, account: account, role: 'hotel_staff') }

  before do
    Permission.find_or_create_by!(slug: 'manage_room_status') { |p| p.name = 'Manage Room Status' }
    Permission.find_or_create_by!(slug: 'manage_requests') { |p| p.name = 'Manage Requests' }

    RolePermission.find_or_create_by!(role: housekeeper_role, permission: Permission.find_by!(slug: 'manage_room_status'))
    RolePermission.find_or_create_by!(role: housekeeper_role, permission: Permission.find_by!(slug: 'manage_requests'))

    UserHotelAccess.create!(user: housekeeper, hotel: hotel, role: housekeeper_role)
    sign_in_as(housekeeper)
  end

  describe 'GET /hotel/:hotel_id/settings' do
    it 'denies access to housekeeper' do
      get hotel_general_settings_path(hotel)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq('You are not authorized to perform this action.')
    end
  end

  describe 'PATCH /hotel/:hotel_id/settings' do
    it 'denies access to housekeeper' do
      patch hotel_general_settings_path(hotel), params: {
        hotel: { time_zone: 'UTC' }
      }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq('You are not authorized to perform this action.')
    end
  end
end
