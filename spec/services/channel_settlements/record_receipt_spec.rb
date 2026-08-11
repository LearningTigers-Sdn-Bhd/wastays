# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelSettlements::RecordReceipt, type: :service do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user, account: hotel.account) }
  let(:source) { create(:booking_source, kind: "ota") }
  let(:payment_method) { create(:hotel_payment_method, hotel:) }
  let(:settlement) do
    create(:channel_settlement, hotel:, booking_source: source, currency: "MYR", expected_net_amount: 90)
  end
  let(:allocation) do
    create(:channel_settlement_allocation, channel_settlement: settlement, currency: "MYR", expected_net_amount: 90)
  end
  let(:attributes) do
    {
      booking_source_id: source.id,
      hotel_payment_method_id: payment_method.id,
      settlement_method: "bank_transfer",
      amount: "90.00",
      currency: "MYR",
      received_at: Time.current,
      external_reference: "OTA-PAYOUT-1",
      notes: "March payout"
    }
  end

  it "records a hotel-scoped receipt and allocations atomically" do
    result = described_class.call(
      hotel:, user:, attributes:, allocations: { allocation.id.to_s => "90.00" }
    )

    expect(result).to be_success
    expect(result.receipt).to have_attributes(
      hotel:, booking_source: source, recorded_by: user, amount: 90.to_d,
      external_reference: "OTA-PAYOUT-1"
    )
    expect(result.receipt.channel_settlement_receipt_allocations.first).to have_attributes(
      channel_settlement_allocation: allocation, amount: 90.to_d, currency: "MYR"
    )
    expect(settlement.reload).to be_received
  end

  it "supports a partial receipt and marks the settlement partially received" do
    result = described_class.call(
      hotel:, user:, attributes: attributes.merge(amount: "40.00"),
      allocations: { allocation.id.to_s => "40.00" }
    )

    expect(result).to be_success
    expect(settlement.reload).to be_partially_received
  end

  it "rejects an allocation belonging to another hotel" do
    allocation
    other_allocation = create(:channel_settlement_allocation)

    expect {
      result = described_class.call(
        hotel:, user:, attributes:, allocations: { other_allocation.id.to_s => "10.00" }
      )
      expect(result).not_to be_success
      expect(result.form.errors[:allocations]).to include("include an unavailable settlement")
    }.not_to change(ChannelSettlementReceipt, :count)
  end

  it "records a real overpayment and marks the settlement overpaid" do
    create(:channel_settlement_receipt_allocation,
      channel_settlement_allocation: allocation,
      channel_settlement_receipt: create(:channel_settlement_receipt,
        hotel:, booking_source: source, currency: "MYR", amount: 50),
      currency: "MYR", amount: 50)

    result = described_class.call(
      hotel:, user:, attributes: attributes.merge(amount: "50.00"),
      allocations: { allocation.id.to_s => "50.00" }
    )

    expect(result).to be_success
    expect(settlement.reload).to be_overpaid
  end

  it "rejects a receipt amount that is not fully allocated" do
    result = described_class.call(
      hotel:, user:, attributes:, allocations: { allocation.id.to_s => "10.00" }
    )

    expect(result).not_to be_success
    expect(result.form.errors[:allocations]).to include("total must equal the receipt amount")
  end


  it "rejects settlement methods that cannot represent an OTA receipt" do
    result = described_class.call(
      hotel:, user:, attributes: attributes.merge(settlement_method: "guest_card"),
      allocations: { allocation.id.to_s => "90.00" }
    )

    expect(result).not_to be_success
    expect(result.form.errors[:settlement_method]).to include("is not included in the list")
  end

  it "normalizes a blank external reference to nil" do
    result = described_class.call(
      hotel:, user:, attributes: attributes.merge(amount: "10.00", external_reference: " "),
      allocations: { allocation.id.to_s => "10.00" }
    )

    expect(result.receipt.external_reference).to be_nil
  end
end
