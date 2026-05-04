require "rails_helper"

RSpec.describe AiConciergeV3::Tools::GetHotelPolicyTool do
  it "returns structured property policy facts" do
    hotel = create(:hotel, :with_ai_concierge)
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00", cancellation_policy: "24 hours")

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy").call

    expect(result["check_in_time"]).to eq("15:00")
    expect(result["check_out_time"]).to eq("12:00")
    expect(result["cancellation_policy"]).to eq("24 hours")
  end
end
