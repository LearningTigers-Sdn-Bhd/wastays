require "rails_helper"

RSpec.describe AiConciergeV3::Tools::HotelInformation::GetNearbyAttractionsTool do
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
          "country" => "Malaysia"
        },
        {
          "name" => "Night Market",
          "description" => "Local food and shopping",
          "address" => "Town Square",
          "city" => "Kuala Lumpur",
          "country" => "Malaysia"
        }
      ]
    )
  end
end
