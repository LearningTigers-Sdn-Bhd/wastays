require "rails_helper"

RSpec.describe AiConciergeV3::Matching::RoomTypeMatcher do
  let(:hotel) { create(:hotel) }
  let(:ocean_villa) { create(:room_type, hotel: hotel, name: "Ocean Villa King") }
  let(:executive_suite) { create(:room_type, hotel: hotel, name: "Executive Suite") }

  it "matches an exact room name mentioned in the query" do
    result = described_class.new(room_types: [ ocean_villa, executive_suite ], query: "Tell me about the Ocean Villa King").call

    expect(result["success"]).to eq(true)
    expect(result.fetch("room_type")).to eq(ocean_villa)
  end

  it "matches a fuzzy room name mention" do
    result = described_class.new(room_types: [ ocean_villa, executive_suite ], query: "Need details for the exec suite").call

    expect(result["success"]).to eq(true)
    expect(result.fetch("room_type")).to eq(executive_suite)
  end

  it "matches reordered room type shorthand" do
    result = described_class.new(room_types: [ ocean_villa, executive_suite ], query: "tell me about the king ocean").call

    expect(result["success"]).to eq(true)
    expect(result.fetch("room_type")).to eq(ocean_villa)
  end

  it "matches small typos and plural variants" do
    result = described_class.new(room_types: [ ocean_villa, executive_suite ], query: "any executive suittes?").call

    expect(result["success"]).to eq(true)
    expect(result.fetch("room_type")).to eq(executive_suite)
  end

  it "returns ambiguous candidates when the query matches multiple room types" do
    ocean_villa
    create(:room_type, hotel: hotel, name: "Ocean Villa Twin")

    result = described_class.new(room_types: hotel.room_types, query: "Tell me about the ocean villa").call

    expect(result["success"]).to eq(false)
    expect(result["error"]).to eq("ambiguous_room_type")
    expect(result["room_type_names"]).to contain_exactly("Ocean Villa King", "Ocean Villa Twin")
  end

  it "returns not found when no room type matches" do
    result = described_class.new(room_types: [ ocean_villa, executive_suite ], query: "Tell me about the mountain cabin").call

    expect(result).to eq(
      "success" => false,
      "error" => "room_type_not_found"
    )
  end
end
