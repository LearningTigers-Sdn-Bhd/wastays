# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::InitializeCheckout do
  let(:hotel) { create(:hotel) }
  let(:quote) { create(:booking_quote, hotel: hotel) }
  let(:callback_url) { "http://example.com/verify" }
  let(:guest_details) { { name: "John Doe", email: "john@example.com", date_of_birth: "1990-05-20" } }
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

  it "initializes checkout for room plus tax total" do
    hotel.update!(sst_enabled: true)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    room_type = create(:room_type, hotel: hotel)
    create(:booking_quote_item, booking_quote: quote, room_type: room_type, nightly_rate_snapshot: { quote.check_in.iso8601 => { "price" => "200.0" } })

    expect(adapter).to receive(:create_checkout_session).with(
      hash_including(amount: 216.to_d)
    ).and_return({ order_id: "order_123" })

    result = subject.call

    expect(result.success?).to be true
  end

  it "excludes tourism tax from the checkout amount" do
    hotel.update!(sst_enabled: true, tourism_tax_enabled: true, tourism_tax_amount: 10.0)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    room_code.update!(is_taxable: true)
    room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    room_code.transaction_code_taxes.create!(primary_tax_key: "tourism_tax")
    room_type = create(:room_type, hotel: hotel)
    create(:booking_quote_item, booking_quote: quote, room_type: room_type, nightly_rate_snapshot: { quote.check_in.iso8601 => { "price" => "200.0" } })
    guest_details[:country] = "Singapore"

    expect(adapter).to receive(:create_checkout_session).with(
      hash_including(amount: 216.to_d)
    ).and_return({ order_id: "order_123" })

    result = subject.call

    expect(result.success?).to be true
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

  it "returns failure when stay restriction is violated" do
    allow(quote).to receive(:stay_restriction_error_message).and_return("Minimum stay is 3 nights")

    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to eq("Minimum stay is 3 nights")
  end

  it "handles standard errors" do
    allow(adapter).to receive(:create_checkout_session).and_raise(StandardError, "Unexpected error")

    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to eq("Unable to initialize payment at the moment.")
  end
end
