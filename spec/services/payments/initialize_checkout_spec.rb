# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::InitializeCheckout do
  let(:hotel) { create(:hotel) }
  let(:quote) { create(:booking_quote, hotel: hotel) }
  let(:callback_url) { "http://example.com/verify" }
  let(:guest_details) { { name: "John Doe", email: "john@example.com" } }
  let(:gateway) { "razorpay" }

  let(:setting) { double("PaymentSetting") }
  let(:adapter) { instance_double(Payments::GatewayAdapters::Razorpay) }

  subject { described_class.new(quote: quote, callback_url: callback_url, gateway: gateway, guest_details: guest_details) }

  before do
    allow(quote.hotel).to receive(:effective_payment_setting).with(gateway).and_return(setting)
    allow(Payments::GatewayRegistry).to receive(:fetch).with(gateway: gateway, setting: setting).and_return(adapter)
  end

  it "successfully initializes a checkout session" do
    expect(adapter).to receive(:create_checkout_session).with(
      hash_including(
        amount: quote.total_amount,
        currency: quote.currency,
        callback_url: callback_url,
        metadata: hash_including(guest_name: "John Doe")
      )
    ).and_return({ order_id: "order_123" })

    result = subject.call
    expect(result.success?).to be true
    expect(result.payload[:order_id]).to eq("order_123")
    expect(result.payload[:gateway]).to eq(gateway)
  end

  it "returns failure when gateway setting is missing" do
    allow(quote.hotel).to receive(:effective_payment_setting).with(gateway).and_return(nil)

    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to eq("Payment gateway is not configured.")
  end

  it "returns failure when gateway is unsupported" do
    allow(Payments::GatewayRegistry).to receive(:fetch).and_raise(Payments::GatewayRegistry::UnsupportedGatewayError, "Unsupported gateway")

    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to eq("Unsupported gateway")
  end

  it "handles standard errors" do
    allow(adapter).to receive(:create_checkout_session).and_raise(StandardError, "Unexpected error")

    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to eq("Unable to initialize payment at the moment.")
  end
end
