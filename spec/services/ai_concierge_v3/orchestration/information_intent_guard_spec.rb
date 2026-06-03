require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::InformationIntentGuard do
  it "routes booking policy phrasing to hotel policy even when interpreted as booking search" do
    result = described_class.new(
      message: "before that, may i know the booking policy?",
      interpretation: interpretation(intent: "booking_search", topic: "booking_search")
    ).call

    expect(result["intent"]).to eq("hotel_policy")
    expect(result["topic"]).to eq("hotel_policy")
    expect(result["tool_hints"]).to eq([ "get_hotel_policy" ])
  end

  it "routes booking advice questions to hotel policy instead of booking search" do
    result = described_class.new(
      message: "what should i aware during booking in this hotel?",
      interpretation: interpretation(intent: "booking_search", topic: "booking_search")
    ).call

    expect(result["intent"]).to eq("hotel_policy")
    expect(result["topic"]).to eq("hotel_policy")
    expect(result["tool_hints"]).to eq([ "get_hotel_policy" ])
  end

  it "routes cancellation questions to hotel policy" do
    result = described_class.new(
      message: "what is the cancellation rule?",
      interpretation: interpretation(intent: "booking_search", topic: "booking_search")
    ).call

    expect(result["intent"]).to eq("hotel_policy")
  end

  it "routes house rules questions to hotel policy" do
    result = described_class.new(
      message: "do you have house rules?",
      interpretation: interpretation(intent: "booking_search", topic: "booking_search")
    ).call

    expect(result["intent"]).to eq("hotel_policy")
    expect(result["topic"]).to eq("hotel_policy")
  end

  it "keeps room availability questions on booking" do
    input = interpretation(intent: "booking_search", topic: "booking_search")

    result = described_class.new(message: "do you have rooms available in july?", interpretation: input).call

    expect(result["intent"]).to eq("booking_search")
  end

  it "keeps clear room booking requests on booking even when a service word is present" do
    input = interpretation(intent: "booking_search", topic: "booking_search")

    result = described_class.new(message: "can i book parking view room on june 23?", interpretation: input).call

    expect(result["intent"]).to eq("booking_search")
  end

  it "routes unscoped facilities questions to hotel information" do
    result = described_class.new(
      message: "available facilities?",
      interpretation: interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => nil })
    ).call

    expect(result["intent"]).to eq("hotel_information")
    expect(result["topic"]).to eq("general_hotel_info")
    expect(result.dig("slots", "room_type_name")).to be_nil
    expect(result["tool_hints"]).to eq([ "get_general_hotel_info" ])
  end

  it "routes hotel amenities questions to hotel information" do
    result = described_class.new(
      message: "may i know hotel amenities",
      interpretation: interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => nil })
    ).call

    expect(result["intent"]).to eq("hotel_information")
  end

  it "routes transportation questions to hotel information" do
    result = described_class.new(
      message: "may i know if the hotel provide transportation",
      interpretation: interpretation(intent: "booking_search", topic: "booking_search")
    ).call

    expect(result["intent"]).to eq("hotel_information")
    expect(result["topic"]).to eq("general_hotel_info")
  end

  it "routes parking questions to hotel information" do
    result = described_class.new(
      message: "is parking available there?",
      interpretation: interpretation(intent: "booking_search", topic: "booking_search")
    ).call

    expect(result["intent"]).to eq("hotel_information")
    expect(result["topic"]).to eq("general_hotel_info")
  end

  it "keeps named room amenities questions on room information" do
    input = interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => "Deluxe Room" })

    result = described_class.new(message: "what amenities does deluxe room have?", interpretation: input).call

    expect(result["intent"]).to eq("room_information")
    expect(result.dig("slots", "room_type_name")).to eq("Deluxe Room")
  end

  def interpretation(intent:, topic: intent, slots: {})
    {
      "intent" => intent,
      "topic" => topic,
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
