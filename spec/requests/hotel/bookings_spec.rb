require 'rails_helper'

RSpec.describe "Hotel::Bookings", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/hotel/bookings/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/hotel/bookings/show"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/hotel/bookings/update"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /cancel" do
    it "returns http success" do
      get "/hotel/bookings/cancel"
      expect(response).to have_http_status(:success)
    end
  end

end
