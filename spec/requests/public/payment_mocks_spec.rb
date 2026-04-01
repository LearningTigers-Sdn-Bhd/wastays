require 'rails_helper'

RSpec.describe "Public::PaymentMocks", type: :request do
  let(:hotel) { create(:hotel) }
  let(:quote) { create(:booking_quote, hotel: hotel) }

  describe "GET /show" do
    it "returns http success" do
      get "/mock_payment", params: { quote_token: quote.token }
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /update" do
    it "returns http success" do
      post "/mock_payment", params: {
        quote_token: quote.token,
        guest_details: {
          name: "Guest",
          email: "guest@example.com",
          phone: "123456",
          government_id: "A123456789",
          gender: "male",
          country: "Malaysia",
          document_type: "passport"
        }
      }
      expect(response).to have_http_status(:found) # Redirects after update
    end
  end
end
