# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelSettlementReceiptAllocation, type: :model do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:source) { create(:booking_source, kind: "ota") }
  let(:ota_party) { create(:booking_billing_party, hotel: hotel, booking: booking, party_kind: "ota", booking_source: source, hotel_corporate_account: nil) }
  let(:folio) { create(:booking_folio, :secondary, hotel: hotel, booking: booking, payer_type: "ota", booking_billing_party: ota_party, hotel_corporate_account: nil) }
  let(:settlement) { create(:channel_settlement, hotel: hotel, booking_source: source, gross_amount: 100, commission_amount: 10, expected_net_amount: 90) }
  let(:allocation) { create(:channel_settlement_allocation, channel_settlement: settlement, booking: booking, booking_folio: folio, gross_amount: 100, commission_amount: 10, expected_net_amount: 90) }
  let(:receipt) { create(:channel_settlement_receipt, hotel: hotel, booking_source: source, currency: "MYR", amount: 90) }

  it "links a receipt to an allocation" do
    join = described_class.new(channel_settlement_receipt: receipt, channel_settlement_allocation: allocation, currency: "MYR", amount: 90)

    expect(join).to be_valid
  end

  it "rejects cross-hotel and cross-source allocations" do
    other_hotel = create(:hotel)
    other_source = create(:booking_source, kind: "ota")
    other_receipt = create(:channel_settlement_receipt, hotel: other_hotel, booking_source: other_source, currency: "MYR", amount: 90)
    join = described_class.new(channel_settlement_receipt: other_receipt, channel_settlement_allocation: allocation, currency: "MYR", amount: 90)

    expect(join).not_to be_valid
    expect(join.errors[:channel_settlement_allocation]).to include("must belong to the receipt hotel", "must use the receipt booking source")
  end

  it "requires one currency and a positive amount" do
    join = described_class.new(channel_settlement_receipt: receipt, channel_settlement_allocation: allocation, currency: "USD", amount: 0)

    expect(join).not_to be_valid
    expect(join.errors[:currency]).to include("must match the receipt currency", "must match the settlement allocation currency")
    expect(join.errors[:amount]).to include("must be greater than 0")
  end
end
