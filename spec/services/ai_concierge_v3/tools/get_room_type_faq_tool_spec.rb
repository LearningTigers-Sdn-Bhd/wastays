require "rails_helper"

RSpec.describe AiConciergeV3::Tools::RoomInformation::GetRoomTypeFaqTool do
  it "returns room faq text for a matched room type" do
    hotel = create(:hotel)
    create(:room_type,
      hotel: hotel,
      name: "Executive Suite",
      faq: "This room includes complimentary minibar refills."
    )

    result = described_class.new(hotel: hotel, query: "What is the faq for the exec suite?").call

    expect(result).to eq(
      "success" => true,
      "room_type_name" => "Executive Suite",
      "faq_text" => "This room includes complimentary minibar refills."
    )
  end

  it "returns not found when the room type cannot be matched" do
    hotel = create(:hotel)
    create(:room_type, hotel: hotel, name: "Executive Suite")

    result = described_class.new(hotel: hotel, query: "faq for mountain cabin").call

    expect(result).to eq(
      "success" => false,
      "error" => "room_type_not_found"
    )
  end
end
