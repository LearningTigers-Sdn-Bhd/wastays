require "rails_helper"
require "ostruct"

RSpec.describe Payments::GatewayAdapters::Curlec do
  let(:setting) { OpenStruct.new(api_key: "key", secret_key: "secret", webhook_secret: "whsec") }
  subject(:adapter) { described_class.new(setting) }

  it "creates a checkout session" do
    result = adapter.create_checkout_session(amount: 10.0, currency: "MYR", description: "Test", metadata: {}, callback_url: "/cb")

    expect(result[:status]).to eq("created")
    expect(result[:checkout_url]).to include("mock_payment_gateway")
  end

  it "maps webhook status to failed when not captured" do
    result = adapter.handle_webhook(payload: { id: "evt", status: "pending" })
    expect(result[:status]).to eq("failed")
  end
end
