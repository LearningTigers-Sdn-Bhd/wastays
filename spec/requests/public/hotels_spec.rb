require 'rails_helper'

RSpec.describe "Public::Hotels", type: :request do
  let(:hotel) { create(:hotel, status: 'approved') }

  describe "GET /index" do
    it "returns http success" do
      get "/hotels"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/hotels/#{hotel.id}"
      expect(response).to have_http_status(:success)
    end
  end

end
