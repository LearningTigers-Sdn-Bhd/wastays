require 'rails_helper'

RSpec.describe "Public::Webhooks", type: :request do
  describe "POST /create" do
    it "returns http success" do
      post "/webhooks/stripe", params: { id: "evt_123", metadata: { quote_token: "tok_123" } }.to_json, headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "rejects a payment callback for a property in training before gateway processing" do
      hotel = create(:hotel, status: "pending_review", training_started_at: Time.current)
      quote = create(:booking_quote, hotel:)

      post "/webhooks/razorpay",
        params: { id: "evt_training", metadata: { quote_token: quote.token } }.to_json,
        headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:forbidden)
      expect(WebhookEvent.find_by!(external_id: "evt_training")).to have_attributes(
        status: "failed",
        error_message: "Real payments are unavailable while this property is in training."
      )
    end
  end
end
