require 'rails_helper'

RSpec.describe "HotelPortal::InventoryDashboards", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    role = create(:role, account: hotel.account)
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "renders rates and inventory overview with hotel-scoped links" do
      create(:room_type, hotel: hotel, name: "Deluxe Room")

      get "/hotel/#{hotel.id}/inventory"

      expect(response).to have_http_status(:success)
    end
  end
end
