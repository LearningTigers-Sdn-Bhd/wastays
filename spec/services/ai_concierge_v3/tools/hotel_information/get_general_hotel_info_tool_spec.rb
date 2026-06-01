require "rails_helper"

RSpec.describe AiConciergeV3::Tools::HotelInformation::GetGeneralHotelInfoTool do
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
end
