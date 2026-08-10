# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelSettlement, type: :model do
  let(:hotel) { create(:hotel) }
  let(:source) { create(:booking_source, kind: "ota") }
  let(:attributes) do
    {
      hotel: hotel,
      booking_source: source,
      provider: "channex",
      channel_manager_reference: "reservation-1",
      collection_by: "ota",
      settlement_method: "virtual_card",
      status: "awaiting_ota_settlement",
      currency: "MYR",
      gross_amount: 100,
      commission_amount: 15,
      expected_net_amount: 85
    }
  end

  it "has the settlement associations" do
    expect(described_class.reflect_on_association(:hotel).macro).to eq(:belongs_to)
    expect(described_class.reflect_on_association(:booking_source).macro).to eq(:belongs_to)
    expect(described_class.reflect_on_association(:channel_settlement_allocations).macro).to eq(:has_many)
    expect(described_class.reflect_on_association(:channel_settlement_receipts).macro).to eq(:has_many)
  end

  it "accepts an OTA settlement with matching amounts" do
    expect(described_class.new(attributes)).to be_valid
  end

  it "requires an OTA booking source" do
    settlement = described_class.new(attributes.merge(booking_source: create(:booking_source, kind: "manual")))

    expect(settlement).not_to be_valid
    expect(settlement.errors[:booking_source]).to include("must be an OTA booking source")
  end

  it "rejects inconsistent net amounts" do
    settlement = described_class.new(attributes.merge(expected_net_amount: 90))

    expect(settlement).not_to be_valid
    expect(settlement.errors[:expected_net_amount]).to include("must equal gross amount minus commission amount")
  end

  it "rejects unsupported currencies and non-positive amounts" do
    settlement = described_class.new(attributes.merge(currency: "wat", gross_amount: -1))

    expect(settlement).not_to be_valid
    expect(settlement.errors[:currency]).to include("is not included in the list")
    expect(settlement.errors[:gross_amount]).to include("must be greater than or equal to 0")
  end

  it "enforces the provider reference identity in the database" do
    create(:channel_settlement, attributes)
    duplicate = build(:channel_settlement, attributes)

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
