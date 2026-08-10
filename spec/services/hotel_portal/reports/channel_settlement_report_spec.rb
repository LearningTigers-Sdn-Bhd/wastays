# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ChannelSettlementReport, type: :service do
  let(:hotel) { create(:hotel) }
  let(:source) { create(:booking_source, key: "ota_channel_report_test", label: "OTA Channel Report Test") }

  def allocation_for(settlement, expected_net_amount: settlement.expected_net_amount)
    create(
      :channel_settlement_allocation,
      channel_settlement: settlement,
      gross_amount: expected_net_amount.to_d + 10,
      commission_amount: 10,
      expected_net_amount: expected_net_amount
    )
  end

  it "groups expected and allocated receipts by provider and currency without a grand total" do
    myr_settlement = create(
      :channel_settlement,
      hotel: hotel,
      booking_source: source,
      provider: "channex",
      channel_manager_reference: "channel-report-myr-1",
      gross_amount: 100,
      commission_amount: 10,
      expected_net_amount: 90,
      currency: "MYR"
    )
    myr_allocation = allocation_for(myr_settlement)
    receipt = create(
      :channel_settlement_receipt,
      hotel: hotel,
      booking_source: source,
      amount: 40,
      currency: "MYR"
    )
    create(
      :channel_settlement_receipt_allocation,
      channel_settlement_allocation: myr_allocation,
      channel_settlement_receipt: receipt,
      amount: 40,
      currency: "MYR"
    )

    second_myr = create(
      :channel_settlement,
      hotel: hotel,
      booking_source: source,
      provider: "channex",
      channel_manager_reference: "channel-report-myr-2",
      gross_amount: 50,
      commission_amount: 5,
      expected_net_amount: 45,
      currency: "MYR"
    )
    allocation_for(second_myr, expected_net_amount: 45)

    usd_settlement = create(
      :channel_settlement,
      hotel: hotel,
      booking_source: source,
      provider: "agoda",
      channel_manager_reference: "channel-report-usd-1",
      gross_amount: 100,
      commission_amount: 10,
      expected_net_amount: 90,
      currency: "USD"
    )
    usd_allocation = allocation_for(usd_settlement)
    usd_receipt = create(
      :channel_settlement_receipt,
      hotel: hotel,
      booking_source: source,
      amount: 90,
      currency: "USD"
    )
    create(
      :channel_settlement_receipt_allocation,
      channel_settlement_allocation: usd_allocation,
      channel_settlement_receipt: usd_receipt,
      amount: 90,
      currency: "USD"
    )

    property_settlement = create(
      :channel_settlement,
      hotel: hotel,
      booking_source: source,
      collection_by: "property",
      channel_manager_reference: "channel-report-property",
      gross_amount: 100,
      commission_amount: 10,
      expected_net_amount: 90
    )

    result = described_class.new(hotel: hotel).call

    expect(property_settlement.collection_by).to eq("property")
    expect(result.rows).to contain_exactly(
      include(
        provider: "channex",
        currency: "MYR",
        expected_net_amount: 135.to_d,
        received_amount: 40.to_d,
        outstanding_amount: 95.to_d,
        variance_amount: -95.to_d,
        expected: 135.to_d,
        received: 40.to_d,
        outstanding: 95.to_d,
        variance: -95.to_d
      ),
      include(
        provider: "agoda",
        currency: "USD",
        expected_net_amount: 90.to_d,
        received_amount: 90.to_d,
        outstanding_amount: 0.to_d,
        variance_amount: 0.to_d
      )
    )
    expect(result.grand_total).to be_nil
    expect(result.currency_totals).to contain_exactly(
      include(currency: "MYR", expected_net_amount: 135.to_d, received_amount: 40.to_d),
      include(currency: "USD", expected_net_amount: 90.to_d, received_amount: 90.to_d)
    )
    expect(result.totals_by_currency.keys).to contain_exactly("MYR", "USD")
  end

  it "uses the settlement expected net when no booking allocation exists" do
    settlement = create(
      :channel_settlement,
      hotel: hotel,
      booking_source: source,
      provider: "channex",
      channel_manager_reference: "channel-report-unallocated",
      gross_amount: 120,
      commission_amount: 20,
      expected_net_amount: 100
    )

    result = described_class.new(hotel: hotel).call

    expect(result.rows).to contain_exactly(include(provider: "channex", currency: "MYR", expected: 100.to_d, received: 0.to_d, outstanding: 100.to_d))
  end
end
