require 'rails_helper'

RSpec.describe "HotelPortal::Arrivals", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:booking) { create(:booking, hotel: hotel, check_in: Date.today) }

  before do
    role = create(:role, account: hotel.account)
    permission = Permission.find_by(slug: "manage_guest_arrival") || Permission.find_by(slug: 'manage_guest_arrival') || create(:permission, slug: 'manage_guest_arrival', name: 'Manage Guest Arrival')
    role.permissions << permission
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
      before do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Room")
      BookingRoom.create!(booking: booking, room_type: room_type, room_type_snapshot: { "name" => room_type.name }, quantity: 1, subtotal: booking.total_amount)
      create(:pre_checkin, booking: booking, status: "completed", document_status: "uploaded")
    end

    it "returns http success" do
      get "/hotel/#{hotel.id}/arrivals"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("View")
      expect(response.body).not_to include("Assign in Room Readiness")
    end

    it 'logs out users whose account has been suspended' do
      user.account.update!(status: 'suspended')

      get "/hotel/#{hotel.id}/arrivals"

      expect(response).to redirect_to(login_path)
      follow_redirect!
      expect(response.body).to include('Your account has been suspended. Please contact support.')
    end
  end
end
