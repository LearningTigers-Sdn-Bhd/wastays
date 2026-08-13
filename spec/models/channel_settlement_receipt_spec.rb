# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelSettlementReceipt, type: :model do
  let(:hotel) { create(:hotel) }
  let(:source) { create(:booking_source, kind: "ota") }
  let(:payment_method) { create(:hotel_payment_method, hotel: hotel) }
  let(:user) { create(:user) }
  let(:attributes) do
    {
      hotel: hotel,
      booking_source: source,
      hotel_payment_method: payment_method,
      recorded_by: user,
      settlement_method: "bank_transfer",
      amount: 85,
      currency: "MYR",
      received_at: Time.current,
      external_reference: "payout-1"
    }
  end

  it "accepts a receipt for an OTA payout" do
    expect(described_class.new(attributes)).to be_valid
  end

  it "requires a payment method from the same hotel" do
    receipt = described_class.new(attributes.merge(hotel_payment_method: create(:hotel_payment_method)))

    expect(receipt).not_to be_valid
    expect(receipt.errors[:hotel_payment_method]).to include("must belong to the receipt hotel")
  end

  it "requires an OTA booking source and a positive amount" do
    receipt = described_class.new(attributes.merge(booking_source: create(:booking_source, kind: "manual"), amount: 0))

    expect(receipt).not_to be_valid
    expect(receipt.errors[:booking_source]).to include("must be an OTA booking source")
    expect(receipt.errors[:amount]).to include("must be greater than 0")
  end
end
