require "rails_helper"

RSpec.describe AiConciergeV3::Tools::HotelInformation::GetHotelFaqTool do
  it "returns hotel faq text when present" do
    hotel = create(:hotel, faq: "Breakfast is served from 7 AM to 10 AM.")

    result = described_class.new(hotel: hotel).call

    expect(result).to eq(
      "success" => true,
      "faq_text" => "Breakfast is served from 7 AM to 10 AM.",
      "source" => "hotel_faq"
    )
  end

  it "returns an unavailable payload when faq is blank" do
    hotel = create(:hotel)

    result = described_class.new(hotel: hotel).call

    expect(result).to eq(
      "success" => false,
      "faq_text" => nil,
      "source" => "hotel_faq"
    )
  end
end
