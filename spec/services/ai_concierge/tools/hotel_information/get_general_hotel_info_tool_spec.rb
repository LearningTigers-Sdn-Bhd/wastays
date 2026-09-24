require "rails_helper"

RSpec.describe AiConcierge::Tools::HotelInformation::GetGeneralHotelInfoTool do
  before do
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([])
  end

  it "returns general hotel details and a short summary" do
    hotel = create(:hotel,
      name: "Wastays Signature",
      address: "10 Beach Road",
      city: "Langkawi",
      country: "Malaysia",
      star_rating: 5
    )

    result = described_class.new(hotel: hotel).call

    expect(result).to include(
      "success" => true,
      "answer_mode" => "fallback",
      "name" => "Wastays Signature",
      "address" => "10 Beach Road",
      "city" => "Langkawi",
      "country" => "Malaysia",
      "star_rating" => 5
    )
    expect(result["summary_text"]).to include("Wastays Signature")
    expect(result["summary_text"]).to include("5-star hotel")
    expect(result["summary_text"]).to include("10 Beach Road, Langkawi, Malaysia")
  end

  it "gives the description from Property Settings, the same text the concierge page shows" do
    hotel = create(:hotel, name: "Wastays Signature", description: "A beach resort on Pantai Cenang.")

    result = described_class.new(hotel: hotel).call

    expect(result["description"]).to eq("A beach resort on Pantai Cenang.")
    expect(result["summary_text"]).to end_with("A beach resort on Pantai Cenang.")
  end

  it "uses selected amenity details in a specific answer" do
    hotel = create(:hotel)
    amenity = Amenity.hotel.find_by!(slug: "swimming_pool")
    hotel.update!(amenities: [ amenity.slug ])
    create(:hotel_amenity_detail, hotel: hotel, amenity: amenity, location: "Roof", opening_hours: "8 AM to 8 PM", fee_information: "Free")

    result = described_class.new(hotel: hotel, query: "Where is the swimming pool?").call

    answer = result.fetch("facts").first.fetch("text")
    expect(answer).to include("Swimming Pool", "Location: Roof", "Hours: 8 AM to 8 PM", "Fees: Free")
  end

  it "reveals only Wi-Fi availability to anonymous chat" do
    hotel = create(:hotel)
    create(:hotel_wifi_network, hotel: hotel, ssid: "SecretSSID", password: "secret-password", connection_instructions: "Scan the lobby card")

    result = described_class.new(hotel: hotel, query: "What is the Wi-Fi password?").call

    answer = result.fetch("facts").first.fetch("text")
    expect(answer).to include("Guest Wi-Fi is available", "after check-in")
    expect(result.to_s).not_to include("SecretSSID", "secret-password", "Scan the lobby card")
  end
end
