require "rails_helper"

RSpec.describe AiConciergeV3::Tools::HotelInformation::GetHotelPolicyTool do
  it "returns hotel policy text when present" do
    hotel = create(:hotel, :with_ai_concierge, policy: [
      {
        "title" => "Pets",
        "content" => "Pets are not allowed."
      }
    ])
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00", cancellation_policy: "24 hours")

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy").call

    expect(result).to include(
      "success" => true,
      "policy_text" => "Pets: Pets are not allowed.",
      "check_in_time" => "15:00",
      "check_out_time" => "12:00",
      "cancellation_policy" => "24 hours",
      "source" => "hotel_policy"
    )
  end

  it "falls back to structured property policy facts when hotel policy is blank" do
    hotel = create(:hotel, :with_ai_concierge)
    create(:property_policy, hotel: hotel, check_in_time: "15:00", check_out_time: "12:00", cancellation_policy: "24 hours")

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy").call

    expect(result).to include(
      "success" => true,
      "policy_text" => nil,
      "check_in_time" => "15:00",
      "check_out_time" => "12:00",
      "cancellation_policy" => "24 hours",
      "source" => "property_policy"
    )
  end

  it "returns an unavailable payload when both hotel policy and property policy are missing" do
    hotel = create(:hotel, :with_ai_concierge)

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy").call

    expect(result).to include(
      "success" => false,
      "policy_text" => nil,
      "check_in_time" => nil,
      "check_out_time" => nil,
      "cancellation_policy" => nil,
      "source" => "property_policy"
    )
  end

  it "ignores malformed entries and supports symbol keys" do
    hotel = create(:hotel, :with_ai_concierge, policy: [
      "invalid",
      {
        title: "Smoking",
        content: "Smoking is not allowed in the rooms."
      },
      {
        "title" => "",
        "content" => ""
      }
    ])

    result = described_class.new(hotel: hotel, policy_topic: "hotel_policy").call

    expect(result).to include(
      "success" => true,
      "policy_text" => "Smoking: Smoking is not allowed in the rooms.",
      "source" => "hotel_policy"
    )
  end
end
