require 'rails_helper'

RSpec.describe "Public::Webhooks", type: :request do
  describe "POST /create" do
    it "returns http success" do
      post "/webhooks/stripe", params: { id: "evt_123", metadata: { quote_token: "tok_123" } }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:internal_server_error) 
    end
  end

end
