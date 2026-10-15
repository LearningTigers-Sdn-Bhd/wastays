# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attractions::PublicHotelLinks do
  let(:hotel) { create(:hotel, google_map_link: "https://www.google.com/maps/place/Hotel/@5.98000,116.07000,15z") }

  it "shows every approved or pending link, nearest first, with missing distances last" do
    farther = create(:attraction, latitude: 6.05, longitude: 116.07)
    nearest = create(:attraction, :pending, latitude: 5.985, longitude: 116.07)
    without_coordinates = create(:attraction, :legacy)
    rejected = create(:attraction, :rejected)
    archived = create(:attraction, :archived)
    other_hotel = create(:hotel)

    [ farther, nearest, without_coordinates, rejected, archived ].each do |attraction|
      create(:hotel_nearby_attraction, hotel: hotel, attraction: attraction)
    end
    create(:hotel_nearby_attraction, hotel: other_hotel, attraction: create(:attraction))

    rows = described_class.call(hotel: hotel)

    expect(rows.map { |row| row.link.attraction }).to eq([ nearest, farther, without_coordinates ])
    expect(rows.map(&:distance_km).first(2)).to all(be_a(Float))
    expect(rows.last.distance_km).to be_nil
    expect(rows.last.maps_url).to include("google.com/maps/search/")
    expect(URI.decode_www_form(URI.parse(rows.last.maps_url).query).to_h.fetch("query")).to include(without_coordinates.name)
  end

  it "keeps all eligible links when hotel coordinates are unavailable" do
    hotel.update!(google_map_link: nil)
    attractions = create_list(:attraction, 11)
    attractions.each { |attraction| create(:hotel_nearby_attraction, hotel: hotel, attraction: attraction) }

    rows = described_class.call(hotel: hotel)

    expect(rows.size).to eq(11)
    expect(rows.map(&:distance_km)).to all(be_nil)
  end
end
