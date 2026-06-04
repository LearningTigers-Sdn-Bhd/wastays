require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::HotelKnowledge::ToolRouter do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:tool_registry) { instance_double(AiConciergeV3::Tools::ToolRegistry) }

  it "routes hotel policy intent to the policy tool" do
    tool = tool_class { { "success" => true, "answer" => "Policy answer" } }
    allow(tool_registry).to receive(:fetch).with("get_hotel_policy").and_return(tool)

    result = route(intent: "hotel_policy", topic: "hotel_policy", message: "what time is check in?")

    expect(result[:reply_type]).to eq(:hotel_policy)
    expect(result[:active_topic]).to eq("hotel_policy")
    expect(result[:active_flow]).to eq("hotel_policy")
    expect(result[:result]["answer"]).to eq("Policy answer")
  end

  it "routes FAQ topic through hotel information to the FAQ tool" do
    tool = tool_class { { "success" => true, "answer" => "FAQ answer" } }
    allow(tool_registry).to receive(:fetch).with("get_hotel_faq").and_return(tool)

    result = route(intent: "hotel_information", topic: "hotel_faq", message: "do you have faq?")

    expect(result[:reply_type]).to eq(:hotel_faq)
    expect(result[:active_topic]).to eq("hotel_faq")
    expect(result[:active_flow]).to eq("hotel_information")
  end

  it "routes general hotel information to the general info tool" do
    tool = tool_class { { "success" => true, "answer" => "General answer" } }
    allow(tool_registry).to receive(:fetch).with("get_general_hotel_info").and_return(tool)

    result = route(intent: "hotel_information", topic: "general_hotel_info", message: "tell me about hotel")

    expect(result[:reply_type]).to eq(:general_hotel_info)
    expect(result[:active_topic]).to eq("general_hotel_info")
  end

  it "routes nearby attractions to the attractions tool" do
    tool = tool_class { { "success" => true, "attractions" => [] } }
    allow(tool_registry).to receive(:fetch).with("get_nearby_attractions").and_return(tool)

    result = route(intent: "nearby_attractions", topic: "nearby_attractions", message: "what is nearby?")

    expect(result[:reply_type]).to eq(:nearby_attractions)
    expect(result[:active_topic]).to eq("nearby_attractions")
    expect(result[:active_flow]).to eq("hotel_information")
  end

  it "routes room information and resolves room reply type" do
    tool = tool_class { { "success" => false, "error" => "ambiguous_room_type" } }
    allow(tool_registry).to receive(:fetch).with("get_room_type_details").and_return(tool)

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
      interpretation: { "intent" => intent, "topic" => topic, "slots" => slots },
      tool_registry: tool_registry
    ).call
  end

  def tool_class(&block)
    Class.new do
      define_method(:initialize) { |**_kwargs| }
      define_method(:call, &block)
    end
  end
end
