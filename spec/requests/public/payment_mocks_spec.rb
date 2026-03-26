require 'rails_helper'

RSpec.describe "Public::PaymentMocks", type: :request do
  describe "GET /show" do
    it "returns http success" do
      get "/public/payment_mocks/show"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/public/payment_mocks/update"
      expect(response).to have_http_status(:success)
    end
  end

end
