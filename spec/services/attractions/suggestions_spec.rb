# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attractions::Suggestions do
  let(:hotel) { create(:hotel, google_map_link: "https://www.google.com/maps/place/Hotel/@5.98000,116.07000,15z") }

  it "returns nearest approved unlinked attractions within 25 kilometers" do
    nearest = create(:attraction, latitude: 5.99, longitude: 116.07)
    farther = create(:attraction, latitude: 6.05, longitude: 116.07)
    create(:attraction, :pending, latitude: 5.985, longitude: 116.07)
    outside = create(:attraction, latitude: 6.30, longitude: 116.07)
    linked = create(:attraction, latitude: 5.981, longitude: 116.07)
    create(:hotel_nearby_attraction, hotel: hotel, attraction: linked)

    results = described_class.call(hotel: hotel)

    expect(results.map(&:attraction)).to eq([ nearest, farther ])
    expect(results.map(&:attraction)).not_to include(outside, linked)
    expect(results.map(&:distance_km)).to all(be_between(0, 25))
  end

  it "returns no suggestions when the hotel has no coordinates" do
    hotel.update!(google_map_link: nil)

    expect(described_class.call(hotel: hotel)).to eq([])
  end

  it "limits the result to ten attractions" do
    11.times { |index| create(:attraction, latitude: 5.981 + (index * 0.001), longitude: 116.07) }

    expect(described_class.call(hotel: hotel).size).to eq(10)
  end
end
