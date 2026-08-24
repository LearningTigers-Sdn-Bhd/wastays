# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attractions::Fingerprint do
  it "normalizes names and coordinates into the same identity" do
    first = described_class.call(name: " Signal-Hill ", latitude: 5.990001, longitude: 116.070001)
    second = described_class.call(name: "signal hill", latitude: 5.990004, longitude: 116.070004)

    expect(first).to eq(second)
  end
end
