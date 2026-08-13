# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::Financials::ConvertSnapshot do
  let(:hotel) { create(:hotel, default_currency: "MYR") }

  before { create(:exchange_rate, base_currency: "USD", currency_code: "MYR", rate: 4.1) }

  it "does not disguise a provider source-total mismatch as FX rounding" do
    financials = {
      currency: "USD", gross_amount: 100.to_d,
      rooms: [ { position: 1, amount: 80.to_d, quantity: 1, days: [], taxes: [], service_fees: [], discounts: [] } ],
      taxes: [], service_fees: [], discounts: []
    }

    result = described_class.call(financials: financials, target_currency: "MYR", hotel: hotel)

    expect(result.rounding_amount).to eq(0.to_d)
    expect(result.payload[:converted_gross_amount]).to eq(410.to_d)
    expect(result.payload.dig(:rooms, 0, :converted_amount)).to eq(328.to_d)
  end

  it "preserves even sub-minor source mismatches instead of absorbing them" do
    financials = {
      currency: "USD", gross_amount: "100.004".to_d,
      rooms: [ {
        position: 1, amount: 80.to_d, quantity: 1, days: [], taxes: [], discounts: [],
        service_fees: [ { kind: "service_fee", amount: 20.to_d, metadata: { "name" => "Fee" } } ]
      } ], taxes: [], service_fees: [], discounts: []
    }

    result = described_class.call(financials: financials, target_currency: "MYR", hotel: hotel)

    expect(result.rounding_amount).to eq(0.to_d)
    expect(result.payload.dig(:rooms, 0, :service_fees, 0, :converted_amount)).to eq(82.to_d)
    expect(result.payload[:converted_gross_amount]).to eq(410.02.to_d)
  end

  it "retains an exact source mismatch even when it rounds to zero in hotel currency" do
    financials = {
      currency: "USD", gross_amount: "100.0001".to_d,
      rooms: [ { position: 1, amount: 100.to_d, quantity: 1, days: [], taxes: [], discounts: [], service_fees: [] } ],
      taxes: [], service_fees: [], discounts: []
    }

    result = described_class.call(financials: financials, target_currency: "MYR", hotel: hotel)

    expect(result.payload[:source_mismatch_amount]).to eq("0.0001".to_d)
    expect(result.payload[:converted_gross_amount] - result.payload.dig(:rooms, 0, :converted_amount)).to eq(0.to_d)
  end

  it "requires an explicit valid source currency" do
    financials = { currency: nil, gross_amount: 10.to_d, rooms: [] }

    expect {
      described_class.call(financials: financials, target_currency: "MYR", hotel: hotel)
    }.to raise_error(ArgumentError, "OTA financial currency is required")
  end
end
