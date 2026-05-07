require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::InformationIntentGuard do
  it "routes unscoped facilities questions to hotel information" do
    result = described_class.new(
      message: "available facilities?",
      interpretation: interpretation(intent: "room_information", slots: { "room_type_name" => nil })
    ).call

    expect(result["intent"]).to eq("hotel_information")
    expect(result["topic"]).to eq("general_hotel_info")
    expect(result.dig("slots", "room_type_name")).to be_nil
    expect(result["tool_hints"]).to eq([ "get_general_hotel_info" ])
  end

  it "routes hotel amenities questions to hotel information" do
    result = described_class.new(
      message: "may i know hotel amenities",
      interpretation: interpretation(intent: "room_information", slots: { "room_type_name" => nil })
    ).call

    expect(result["intent"]).to eq("hotel_information")
  end

  it "keeps named room amenities questions on room information" do
    input = interpretation(intent: "room_information", slots: { "room_type_name" => "Deluxe Room" })

    result = described_class.new(message: "what amenities does deluxe room have?", interpretation: input).call

    expect(result["intent"]).to eq("room_information")
    expect(result.dig("slots", "room_type_name")).to eq("Deluxe Room")
  end

  def interpretation(intent:, slots: {})
    {
      "intent" => intent,
      "topic" => intent,
      "confidence" => 1.0,
      "slots" => slots,
      "tool_hints" => [],
      "conversation_signals" => {
        "is_reset" => false,
        "is_resume" => false,
        "is_correction" => false,
        "starts_new_booking_branch" => false,
        "end_conversation" => false
      }
    }
  end
end
