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

  it "reuses an approved attraction with the same URL and a different stored name" do
    attraction = create(:attraction, name: "Imago Mall", google_maps_url: url,
      latitude: 5.99211, longitude: 116.08122)

    result = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user)

    expect(result).to be_success
    expect(result.attraction).to eq(attraction)
    expect(result).to be_reused
    expect(HotelNearbyAttraction.where(hotel: hotel, attraction: attraction).count).to eq(1)
  end

  it "links the selected attraction without parsing its outdated Google Maps URL" do
    attraction = create(:attraction, name: "Maybank Gaya Street", google_maps_url: url)

    first = described_class.call(hotel: hotel, attraction_id: attraction.id, submitted_by: user)
    second = described_class.call(hotel: hotel, attraction_id: attraction.id, submitted_by: user)

    expect(first).to be_success
    expect(second).to be_success
    expect(first.attraction).to eq(attraction)
    expect(second.hotel_nearby_attraction).to eq(first.hotel_nearby_attraction)
    expect(HotelNearbyAttraction.where(hotel: hotel, attraction: attraction).count).to eq(1)
    expect(Attraction.where(name: "Signal Hill")).to be_empty
  end

  it "rejects a selected attraction that is not active" do
    attraction = create(:attraction, :archived)

    result = described_class.call(hotel: hotel, attraction_id: attraction.id, submitted_by: user)

    expect(result).not_to be_success
    expect(hotel.hotel_nearby_attractions).to be_empty
  end

  it "links the kept attraction when the pasted URL matches a merged record" do
    parsed = Attractions::GoogleMapsUrlParser.call(url).parsed
    target = create(:attraction, name: "Signal Hill Observatory")
    create(:attraction, :archived, name: parsed.name, latitude: parsed.latitude,
      longitude: parsed.longitude, merged_into: target)

    result = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user)

    expect(result).to be_success
    expect(result.attraction).to eq(target)
    expect(result.hotel_nearby_attraction.attraction).to eq(target)
  end

  it "does not link a merged record that was incorrectly approved" do
    parsed = Attractions::GoogleMapsUrlParser.call(url).parsed
    target = create(:attraction, name: "Signal Hill Observatory")
    create(:attraction, name: parsed.name, latitude: parsed.latitude,
      longitude: parsed.longitude, merged_into: target)

    result = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user)

    expect(result).to be_success
    expect(result.attraction).to eq(target)
    expect(hotel.hotel_nearby_attractions.sole.attraction).to eq(target)
  end

  it "rejects a pasted URL when its merged target is unavailable" do
    parsed = Attractions::GoogleMapsUrlParser.call(url).parsed
    target = create(:attraction, :archived)
    create(:attraction, :archived, name: parsed.name, latitude: parsed.latitude,
      longitude: parsed.longitude, merged_into: target)

    result = described_class.call(hotel: hotel, google_maps_url: url, submitted_by: user)

    expect(result).not_to be_success
    expect(hotel.hotel_nearby_attractions).to be_empty
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
