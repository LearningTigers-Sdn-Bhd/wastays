require 'rails_helper'

RSpec.describe "HotelPortal::Arrivals", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/hotel/arrivals"
      expect(response).to have_http_status(:success)
    end

    it 'logs out users whose account has been suspended' do
      user.account.update!(status: 'suspended')

      get "/hotel/arrivals"

      expect(response).to redirect_to(login_path)
      follow_redirect!
      expect(response.body).to include('Your account has been suspended. Please contact support.')
    end
  end
end
