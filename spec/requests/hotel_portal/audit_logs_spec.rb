require 'rails_helper'

RSpec.describe "HotelPortal::AuditLogs", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/hotel/audit_logs"
      expect(response).to have_http_status(:success)
    end
  end
end
