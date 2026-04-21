require "rails_helper"
require "ostruct"

RSpec.describe Payments::GatewayAdapters::Razorpay do
  let(:setting) { OpenStruct.new(api_key: "key", secret_key: "secret", webhook_secret: "whsec") }
  subject(:adapter) { described_class.new(setting) }

  it "verifies webhook signature" do
    payload = { event: "payment.captured" }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", "whsec", payload)

    expect(adapter.verify_webhook(payload: payload, signature: signature)).to be(true)
    expect(adapter.verify_webhook(payload: payload, signature: "bad")).to be(false)
  end

  it "handles webhook payload mapping" do
    result = adapter.handle_webhook(payload: { event: "payment.captured", payload: { payment: { entity: { id: "pay_1", order_id: "order_1", method: "card", status: "captured", amount: 1000, currency: "MYR", notes: { quote_token: "tok" } } } } })

    expect(result[:status]).to eq("captured")
    expect(result[:external_reference]).to eq("pay_1")
    expect(result[:gateway_order_id]).to eq("order_1")
  end
end
