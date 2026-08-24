# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attractions::FindOrCreateAndLink do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:url) { "https://www.google.com/maps/place/Signal+Hill/@5.99211,116.08122,15z" }

  it "creates a pending attraction and hotel link" do
    result = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user, description: "Sunset view")

    expect(result).to be_success
    expect(result).to be_created
    expect(result.attraction).to be_status_pending
    expect(result.attraction.source_hotel).to eq(hotel)
    expect(result.hotel_nearby_attraction.description).to eq("Sunset view")
  end

  it "reuses an approved duplicate" do
    parsed = Attractions::GoogleMapsUrlParser.call(url).parsed
    attraction = create(:attraction, name: parsed.name, normalized_name: parsed.normalized_name,
      latitude: parsed.latitude, longitude: parsed.longitude, coordinate_fingerprint: parsed.fingerprint)

    result = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user)

    expect(result).to be_success
    expect(result).to be_reused
    expect(result.attraction).to eq(attraction)
    expect(HotelNearbyAttraction.where(hotel: hotel, attraction: attraction).count).to eq(1)
  end

  it "does not create a second link for the same hotel" do
    first = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user)
    second = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user)

    expect(second).to be_success
    expect(second.hotel_nearby_attraction).to eq(first.hotel_nearby_attraction)
  end

  it "rejects an inactive duplicate" do
    parsed = Attractions::GoogleMapsUrlParser.call(url).parsed
    create(:attraction, :archived, name: parsed.name, normalized_name: parsed.normalized_name,
      latitude: parsed.latitude, longitude: parsed.longitude, coordinate_fingerprint: parsed.fingerprint)

    result = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user)

    expect(result).not_to be_success
    expect(result.error).to include("archived")
  end

  it "approves a new attraction for an administrator" do
    result = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user, approve: true)

    expect(result.attraction).to be_status_approved
    expect(result.attraction.reviewed_by).to eq(user)
  end
end
