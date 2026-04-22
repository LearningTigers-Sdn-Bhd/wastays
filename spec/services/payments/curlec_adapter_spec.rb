require "rails_helper"
require "ostruct"

RSpec.describe Payments::GatewayAdapters::Curlec do
  let(:setting) { OpenStruct.new(api_key: "key", secret_key: "secret", webhook_secret: "whsec") }
  subject(:adapter) { described_class.new(setting) }

  describe "#create_checkout_session" do
    it "returns created checkout payload" do
      payload = adapter.create_checkout_session(
        amount: 100.5,
        currency: "MYR",
        description: "Booking",
        metadata: { quote_token: "tok_1" },
        callback_url: "/payments/verify"
      )

      expect(payload[:id]).to start_with("curlec_intent_")
      expect(payload[:status]).to eq("created")
      expect(payload[:amount]).to eq(100.5)
      expect(payload[:currency]).to eq("MYR")
      expect(payload[:checkout_url]).to include("/mock_payment_gateway")
    end
  end

  describe "#verify_client_callback" do
    it "returns captured payload and keeps external reference when provided" do
      result = adapter.verify_client_callback(payment_response: { external_reference: "evt_123" })

      expect(result[:status]).to eq("captured")
      expect(result[:external_reference]).to eq("evt_123")
    end
  end

  describe "#verify_webhook" do
    it "returns true in test env" do
      expect(adapter.verify_webhook(payload: "{}", signature: "anything")).to be(true)
    end
  end

  describe "#handle_webhook" do
    it "maps captured status" do
      result = adapter.handle_webhook(payload: { id: "evt_1", status: "captured", amount: 5000, currency: "MYR", metadata: { source: "webhook" } })

      expect(result).to include(external_reference: "evt_1", status: "captured", amount: 5000, currency: "MYR")
      expect(result[:metadata]).to eq({ source: "webhook" })
    end

    it "maps non-captured status to failed" do
      result = adapter.handle_webhook(payload: { id: "evt_2", status: "failed" })
      expect(result[:status]).to eq("failed")
    end
  end
end
