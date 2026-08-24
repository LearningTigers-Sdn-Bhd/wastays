require "rails_helper"

RSpec.describe AiConcierge::Tools::HotelInformation::GetNearbyAttractionsTool do
  it "returns the full nearby attractions list" do
    hotel = create(:hotel)
    create(:nearby_attraction, hotel: hotel, name: "Sky Bridge", description: "Scenic landmark", address: "Cable Car Station")
    create(:nearby_attraction, hotel: hotel, name: "Night Market", description: "Local food and shopping", address: "Town Square")

    result = described_class.new(hotel: hotel).call

    expect(result).to eq(
      "success" => true,
      "attractions" => [
        {
          "name" => "Sky Bridge",
          "description" => "Scenic landmark",
          "address" => "Cable Car Station",
          "city" => "Kuala Lumpur",
          "country" => "Malaysia",
          "google_maps_url" => nil,
          "distance_km" => nil
        },
        {
          "name" => "Night Market",
          "description" => "Local food and shopping",
          "address" => "Town Square",
          "city" => "Kuala Lumpur",
          "country" => "Malaysia",
          "google_maps_url" => nil,
          "distance_km" => nil
        }
      ]
    )
  end

  it "includes linked pending attractions and excludes rejected or archived attractions" do
    hotel = create(:hotel)
    other_hotel = create(:hotel, account: hotel.account)
    own_pending = create(:attraction, status: "pending", source_hotel: hotel, name: "Own pending")
    other_pending = create(:attraction, status: "pending", source_hotel: other_hotel, name: "Other pending")
    rejected = create(:attraction, :rejected, source_hotel: hotel, name: "Rejected")
    archived = create(:attraction, status: "archived", source_hotel: hotel, name: "Archived")

    [ own_pending, other_pending, rejected, archived ].each do |attraction|
      create(:hotel_nearby_attraction, hotel: hotel, attraction: attraction)
    end

    names = described_class.new(hotel: hotel).call.fetch("attractions").pluck("name")

    expect(names).to eq([ "Own pending", "Other pending" ])
  end
end
