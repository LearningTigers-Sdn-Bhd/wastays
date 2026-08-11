# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::ChannexFinancialPayloadNormalizer do
  subject(:normalized) { described_class.call(payload) }

  let(:payload) do
    JSON.parse(Rails.root.join("spec/fixtures/channel_managers/channex_aurora_financial_booking.json").read)
  end

  it "normalizes the Aurora Crown Booking.com financials using decimals" do
    expect(normalized).to include(
      currency: "USD",
      gross_amount: BigDecimal("536.96"),
      commission_amount: BigDecimal("0"),
      payment_collect: "property",
      occupancy: { adults: 2, children: 0, infants: 0 }
    )
    expect(normalized[:gross_amount]).to be_a(BigDecimal)

    room = normalized[:rooms].sole
    expect(room).to include(
      room_type_id: "db7b5c2d-ffb6-4b1d-9290-2a7e9c4423da",
      rate_plan_id: "e12016f5-71bf-4f79-ba19-27d643198df3",
      quantity: 1,
      occupancy: { adults: 2, children: 0, infants: 0 },
      amount: BigDecimal("363.12"),
      gross_amount: BigDecimal("536.96")
    )
    expect(room[:days]).to contain_exactly(include(date: "2026-08-11", amount: BigDecimal("363.12")))
  end

  it "classifies a service charge carried in the provider taxes array as a fee" do
    room = normalized[:rooms].sole

    expect(room[:service_fees].sole).to include(
      kind: "service_fee", amount: BigDecimal("123.00"), inclusive: false,
      metadata: include("name" => "Cleaning fee", "type" => "Service Charge")
    )
    expect(room[:taxes].sole).to include(
      kind: "tax", amount: BigDecimal("50.84"), inclusive: false,
      metadata: include("name" => "VAT (14%)", "type" => "Value Added Tax (VAT)")
    )
    expect(normalized[:totals]).to include(
      room_amount: BigDecimal("363.12"),
      tax_amount: BigDecimal("50.84"),
      service_fee_amount: BigDecimal("123.00"),
      discount_amount: BigDecimal("0"),
      calculated_amount: BigDecimal("536.96")
    )
  end

  it "keeps only explicitly safe scalar metadata" do
    expect(normalized[:metadata]).to include(
      "booking_id" => "1ca8abf5-5466-449d-b45c-eca6d8c781db",
      "ota_name" => "BookingCom",
      "payment_type" => "credit_card"
    )
    expect(normalized.to_s).not_to include("4111111111111111", "must-not-be-retained", "guarantee")
  end

  it "marks room-shell cancellations and missing-currency payloads as incomplete" do
    cancellation = described_class.call(
      data: { attributes: { status: "cancelled", amount: "100", currency: "USD", rooms: [ { room_type_id: "room-1" } ] } }
    )
    missing_currency = described_class.call(
      data: { attributes: { amount: "100", rooms: [ { room_type_id: "room-1", amount: "100" } ] } }
    )

    expect(cancellation).to include(breakdown_present: true, breakdown_complete: false)
    expect(missing_currency).to include(breakdown_present: true, breakdown_complete: false)
    expect(normalized).to include(breakdown_present: true, breakdown_complete: true)
  end

  it "produces the same ordered structure for repeated calls" do
    expect(described_class.call(payload)).to eq(described_class.call(payload))
  end

  it "accepts JSON:API attributes, date-keyed days, and symbol keys" do
    result = described_class.call(
      data: {
        attributes: {
          currency: "usd",
          amount: "21.25",
          rooms: [ {
            room_type_id: "room-1",
            occupancy: { adults: 1 },
            days: { "2027-01-02" => "10.25", "2027-01-01" => { price: "11.00" } }
          } ]
        }
      }
    )

    expect(result[:gross_amount]).to eq(BigDecimal("21.25"))
    expect(result[:rooms].sole[:amount]).to eq(BigDecimal("21.25"))
    expect(result[:rooms].sole[:days].pluck(:date)).to eq(%w[2027-01-01 2027-01-02])
    expect(result[:rooms].sole[:occupancy]).to eq(adults: 1, children: 0, infants: 0)
  end
end
