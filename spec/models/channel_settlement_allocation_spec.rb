# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelSettlementAllocation, type: :model do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:source) { create(:booking_source, kind: "ota") }
  let(:ota_party) { create(:booking_billing_party, hotel: hotel, booking: booking, party_kind: "ota", booking_source: source, hotel_corporate_account: nil) }
  let(:folio) { create(:booking_folio, :secondary, hotel: hotel, booking: booking, payer_type: "ota", booking_billing_party: ota_party, hotel_corporate_account: nil) }
  let(:settlement) do
    create(:channel_settlement,
      hotel: hotel, booking_source: source, gross_amount: 100,
      commission_amount: 10, expected_net_amount: 90)
  end
  let(:attributes) do
    {
      channel_settlement: settlement,
      booking: booking,
      booking_folio: folio,
      currency: "MYR",
      gross_amount: 100,
      commission_amount: 10,
      expected_net_amount: 90
    }
  end

  it "links a settlement to a booking folio" do
    allocation = described_class.new(attributes)

    expect(allocation).to be_valid
    expect(allocation.channel_settlement).to eq(settlement)
    expect(allocation.booking_folio).to eq(folio)
  end

  it "rejects a booking from another hotel" do
    other_booking = create(:booking)
    allocation = described_class.new(attributes.merge(booking: other_booking, booking_folio: create(:booking_folio, booking: other_booking, hotel: other_booking.hotel)))

    expect(allocation).not_to be_valid
    expect(allocation.errors[:booking]).to include("must belong to the settlement hotel")
  end

  it "rejects a guest folio even when it belongs to the booking" do
    guest_folio = create(:booking_folio, hotel: hotel, booking: booking)
    allocation = described_class.new(attributes.merge(booking_folio: guest_folio))

    expect(allocation).not_to be_valid
    expect(allocation.errors[:booking_folio]).to include("must be an OTA payer folio")
  end

  it "rejects a folio from a different booking" do
    other_booking = create(:booking, hotel: hotel)
    allocation = described_class.new(attributes.merge(booking_folio: create(:booking_folio, booking: other_booking, hotel: hotel)))

    expect(allocation).not_to be_valid
    expect(allocation.errors[:booking_folio]).to include("must belong to the allocated booking")
  end

  it "requires the settlement currency and amount components to match" do
    allocation = described_class.new(attributes.merge(currency: "USD", expected_net_amount: 95))

    expect(allocation).not_to be_valid
    expect(allocation.errors[:currency]).to include("must match the settlement currency")
    expect(allocation.errors[:expected_net_amount]).to include("must equal gross amount minus commission amount")
  end
end
