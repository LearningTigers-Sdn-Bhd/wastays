require "rails_helper"

RSpec.describe AiConcierge::Tools::RoomInformation::GetRoomTypeDetailsTool do
  it "returns room details and amenity names for a fuzzy match" do
    hotel = create(:hotel)
    room_type = create(:room_type,
      hotel: hotel,
      name: "Executive Suite",
      description: "Large suite with sea view.",
      max_adults: 3,
      max_children: 2,
      amenities: %w[wifi balcony tv]
    )

    result = described_class.new(hotel: hotel, query: "Tell me about the exec suite").call

    expect(result).to eq(
      "success" => true,
      "matched_room_type_id" => room_type.id,
      "room_type_name" => "Executive Suite",
      "description" => "Large suite with sea view.",
      "max_adults" => 3,
      "max_children" => 2,
      "amenities" => [ "Free WiFi", "Balcony / Terrace", "Flat-screen TV" ]
    )
  end

  it "returns ambiguous candidates when the room query matches multiple room types" do
    hotel = create(:hotel)
    create(:room_type, hotel: hotel, name: "Ocean Villa King")
    create(:room_type, hotel: hotel, name: "Ocean Villa Twin")

    result = described_class.new(hotel: hotel, query: "ocean villa details").call

    expect(result["success"]).to eq(false)
    expect(result["error"]).to eq("ambiguous_room_type")
    expect(result["room_type_names"]).to contain_exactly("Ocean Villa King", "Ocean Villa Twin")
  end
end
