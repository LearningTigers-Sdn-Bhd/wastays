require "rails_helper"

RSpec.describe AiConcierge::Orchestration::HotelKnowledge::ToolRouter do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  it "routes hotel policy intent to the policy tool" do
    stub_tool(AiConcierge::Tools::HotelInformation::GetHotelPolicyTool, "success" => true, "answer" => "Policy answer")

    result = route(intent: "hotel_policy", topic: "hotel_policy", message: "what time is check in?")

    expect(result[:reply_type]).to eq(:hotel_policy)
    expect(result[:active_topic]).to eq("hotel_policy")
    expect(result[:active_flow]).to eq("hotel_policy")
    expect(result[:result]["answer"]).to eq("Policy answer")
  end

  it "routes FAQ topic through hotel information to the FAQ tool" do
    stub_tool(AiConcierge::Tools::HotelInformation::GetHotelFaqTool, "success" => true, "answer" => "FAQ answer")

    result = route(intent: "hotel_information", topic: "hotel_faq", message: "do you have faq?")

    expect(result[:reply_type]).to eq(:hotel_faq)
    expect(result[:active_topic]).to eq("hotel_faq")
    expect(result[:active_flow]).to eq("hotel_information")
  end

  it "routes general hotel information to the general info tool" do
    stub_tool(AiConcierge::Tools::HotelInformation::GetGeneralHotelInfoTool, "success" => true, "answer" => "General answer")

    result = route(intent: "hotel_information", topic: "general_hotel_info", message: "tell me about hotel")

    expect(result[:reply_type]).to eq(:general_hotel_info)
    expect(result[:active_topic]).to eq("general_hotel_info")
  end

  it "routes nearby attractions to the attractions tool" do
    stub_tool(AiConcierge::Tools::HotelInformation::GetNearbyAttractionsTool, "success" => true, "attractions" => [])

    result = route(intent: "nearby_attractions", topic: "nearby_attractions", message: "what is nearby?")

    expect(result[:reply_type]).to eq(:nearby_attractions)
    expect(result[:active_topic]).to eq("nearby_attractions")
    expect(result[:active_flow]).to eq("hotel_information")
  end

  it "routes room information and resolves room reply type" do
    stub_tool(AiConcierge::Tools::RoomInformation::GetRoomTypeDetailsTool, "success" => false, "error" => "ambiguous_room_type")

    result = route(
      intent: "room_information",
      topic: "room_information",
      message: "tell me about ocean villa",
      slots: { "room_type_name" => "Ocean Villa" }
    )

    expect(result[:reply_type]).to eq(:ambiguous_room_type)
    expect(result[:active_topic]).to eq("room_information")
    expect(result[:active_flow]).to eq("room_information")
  end

  def route(intent:, topic:, message:, slots: {})
    described_class.new(
      hotel: hotel,
      message: message,
      interpretation: { "intent" => intent, "topic" => topic, "slots" => slots }
    ).call
  end

  # The router's job is picking the class, so the classes are named here rather
  # than fetched by string: a typo is a NameError now, not a nil.
  def stub_tool(klass, result)
    allow(klass).to receive(:new).and_return(instance_double(klass, call: result))
  end
end
