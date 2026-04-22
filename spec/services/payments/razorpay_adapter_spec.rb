require "rails_helper"
require "ostruct"

RSpec.describe Payments::GatewayAdapters::Razorpay do
  class FakeHttpsSuccess
    attr_reader :body

    def initialize(body)
      @body = body
    end

    def code
      "200"
    end

    def to_hash
      {}
    end

    def is_a?(klass)
      klass == Net::HTTPSuccess || super
    end
  end

  let(:setting) do
    OpenStruct.new(
      api_key: "rzp_test_key",
      secret_key: "rzp_test_secret",
      webhook_secret: "whsec"
    )
  end

  let(:adapter) { described_class.new(setting) }

  describe "#create_checkout_session" do
    it "calls Razorpay order endpoint under /v1" do
      fake_client = instance_double(Net::HTTP)
      captured_path = nil

      allow(adapter).to receive(:http_client).and_return(fake_client)
      allow(fake_client).to receive(:request) do |request|
        captured_path = request.path
        FakeHttpsSuccess.new({ id: "order_123", amount: 32155, currency: "MYR" }.to_json)
      end

      adapter.create_checkout_session(
        amount: 321.55,
        currency: "MYR",
        description: "desc",
        metadata: { quote_token: "tok_1" },
        callback_url: "/payments/verify"
      )

      expect(captured_path).to eq("/v1/orders")
    end
  end

  describe "#verify_client_callback" do
    it "calls Razorpay payment endpoint under /v1" do
      fake_client = instance_double(Net::HTTP)
      captured_path = nil

      order_id = "order_123"
      payment_id = "pay_123"
      signature = OpenSSL::HMAC.hexdigest("SHA256", setting.secret_key, "#{order_id}|#{payment_id}")

      allow(adapter).to receive(:http_client).and_return(fake_client)
      allow(fake_client).to receive(:request) do |request|
        captured_path = request.path
        FakeHttpsSuccess.new({ id: payment_id, status: "captured", amount: 32155, currency: "MYR", notes: {} }.to_json)
      end

      adapter.verify_client_callback(
        payment_response: {
          razorpay_payment_id: payment_id,
          razorpay_order_id: order_id,
          razorpay_signature: signature
        }
      )

      expect(captured_path).to eq("/v1/payments/pay_123")
    end
  end
end
