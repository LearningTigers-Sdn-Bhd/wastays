# frozen_string_literal: true

require "rails_helper"

RSpec.describe OtaRateVariancePolicy, type: :model do
  let(:hotel) { create(:hotel) }

  it "applies the approved recommended thresholds in the hotel currency" do
    policy = described_class.create!(hotel: hotel, mode: "recommended")

    expect(policy).to have_attributes(
      currency: hotel.default_currency,
      maximum_percentage: 1.to_d,
      maximum_amount_per_room_night: 10.to_d
    )
  end

  it "stores harmless default thresholds for strict mode" do
    policy = described_class.new(hotel: hotel, mode: "strict", currency: "MYR")

    expect(policy).to be_valid
  end

  it "uses database defaults for omitted custom thresholds and rejects negative thresholds" do
    missing = described_class.new(hotel: hotel, mode: "custom", currency: "MYR", maximum_percentage: 1)
    negative = described_class.new(
      hotel: hotel,
      mode: "custom",
      currency: "MYR",
      maximum_percentage: 1,
      maximum_amount_per_room_night: -1
    )

    expect(missing).to be_valid
    expect(missing.maximum_amount_per_room_night).to eq(10.to_d)
    expect(negative).not_to be_valid
    expect(negative.errors[:maximum_amount_per_room_night]).to include("must be greater than or equal to 0")
  end

  it "normalizes and validates currency" do
    policy = described_class.new(hotel: hotel, mode: "strict", currency: " usd ")
    invalid = described_class.new(hotel: hotel, mode: "strict", currency: "wat")

    expect(policy).to be_valid
    expect(policy.currency).to eq("USD")
    expect(invalid).not_to be_valid
  end

  it "enforces one hotel-level policy in the model and database" do
    described_class.create!(hotel: hotel, mode: "strict", currency: "MYR")
    duplicate = described_class.new(hotel: hotel, mode: "strict", currency: "MYR")

    expect(duplicate).not_to be_valid
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
