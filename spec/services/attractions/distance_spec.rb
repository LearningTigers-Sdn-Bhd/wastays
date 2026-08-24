# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attractions::Distance do
  it "calculates the Haversine distance in kilometers" do
    distance = described_class.kilometers(5.98, 116.07, 5.99, 116.07)

    expect(distance).to be_within(0.01).of(1.11)
  end
end
