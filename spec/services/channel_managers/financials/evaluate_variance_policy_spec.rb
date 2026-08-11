# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::Financials::EvaluateVariancePolicy do
  it "uses recommended defaults when the hotel has no saved policy" do
    hotel = create(:hotel, default_currency: "MYR")

    result = described_class.call(hotel:, variance_amount: -1, expected_amount: 100, room_nights: 1)

    expect(result.accepted).to be(true)
    expect(result.snapshot).to eq(
      "mode" => "recommended", "maximum_percentage" => "1.0",
      "maximum_amount_per_room_night" => "10.0", "currency" => "MYR"
    )
  end

  it "requires zero variance in strict mode" do
    hotel = create(:hotel)
    create(:ota_rate_variance_policy, hotel:, mode: "strict")

    expect(described_class.call(hotel:, variance_amount: 0, expected_amount: 0, room_nights: 0).accepted).to be(true)
    expect(described_class.call(hotel:, variance_amount: 0.01, expected_amount: 100, room_nights: 1).accepted).to be(false)
  end

  it "enforces both custom percentage and per-room-night amount limits" do
    hotel = create(:hotel)
    create(:ota_rate_variance_policy, hotel:, mode: "custom",
      maximum_percentage: 5, maximum_amount_per_room_night: 2)

    expect(described_class.call(hotel:, variance_amount: 4, expected_amount: 100, room_nights: 2).accepted).to be(true)
    expect(described_class.call(hotel:, variance_amount: 5, expected_amount: 100, room_nights: 2).accepted).to be(false)
    expect(described_class.call(hotel:, variance_amount: 4, expected_amount: 50, room_nights: 2).accepted).to be(false)
  end
end
