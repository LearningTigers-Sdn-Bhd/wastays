require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::HotelKnowledge::Orchestrator do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect, pending_question: "confirm_selection", slots_payload: slots_payload) }
  let(:selected_option) do
    {
      "selection_id" => "sel_1",
      "room_type_name" => "Deluxe Room",
      "check_in" => "2026-08-03",
      "check_out" => "2026-08-05"
    }
  end
  let(:branch) do
    {
      "branch_id" => "branch-1",
      "target_month" => 8,
      "target_year" => 2026,
      "confirmation_candidate" => selected_option,
      "selected_option" => selected_option
    }
  end
  let(:slots_payload) do
    AiConciergeV3::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")
  end

  before do
    create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", check_out_time: "11:00 AM")
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([])
  end

  it "returns a general hotel information domain result" do
    hotel.update!(amenities: [ Hotel::HOTEL_AMENITIES.first.fetch(:id) ])

    result = described_class.new(
      hotel: hotel,
      message: "tell me about the hotel",
      interpretation: interpretation(intent: "hotel_information", topic: "general_hotel_info"),
      conversation_state: conversation_state,
      pause: false
    ).call

    expect(result[:reply_type]).to eq(:general_hotel_info)
    expect(result[:active_topic]).to be_nil
    expect(result[:active_flow]).to be_nil
    expect(result.dig(:extra_context, :result, "name")).to eq(hotel.name)
    expect(result.dig(:extra_context, :result, "amenities")).to be_present
    expect(result.dig(:slots_payload, "booking_task", "status")).to eq("waiting_for_confirmation")
    expect(result.dig(:slots_payload, "information_task", "intent")).to eq("hotel_information")
  end

  it "returns a hotel faq domain result" do
    doc = create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "General", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: doc, chunk_index: 0, content: "Q: Breakfast?\nA: From 7 AM.")

    result = described_class.new(
      hotel: hotel,
      message: "do you have an faq?",
      interpretation: interpretation(intent: "hotel_information", topic: "hotel_faq"),
      conversation_state: conversation_state,
      pause: false
    ).call

    expect(result[:reply_type]).to eq(:hotel_faq)
    expect(result.dig(:extra_context, :result, "faq_text")).to include("Breakfast?")
  end

  it "returns a nearby attractions domain result" do
    create(:nearby_attraction, hotel: hotel, name: "Sky Bridge", description: "Scenic landmark")

    result = described_class.new(
      hotel: hotel,
      message: "what attractions are nearby?",
      interpretation: interpretation(intent: "nearby_attractions", topic: "nearby_attractions"),
      conversation_state: conversation_state,
      pause: false
    ).call

    expect(result[:reply_type]).to eq(:nearby_attractions)
    expect(result.dig(:extra_context, :result, "attractions").first["name"]).to eq("Sky Bridge")
  end

  it "returns a room information success domain result" do
    room_type = create(:room_type, hotel: hotel, name: "Executive Suite", description: "Large suite.", amenities: %w[wifi balcony])

    result = described_class.new(
      hotel: hotel,
      message: "tell me about the executive suite",
      interpretation: interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => "Executive Suite" }),
      conversation_state: conversation_state,
      pause: false
    ).call

    expect(result[:reply_type]).to eq(:room_type_details)
    expect(result.dig(:extra_context, :result, "matched_room_type_id")).to eq(room_type.id)
    expect(result.dig(:extra_context, :result, "amenities")).to include("Free WiFi", "Balcony / Terrace")
  end

  it "returns an ambiguous room information domain result" do
    create(:room_type, hotel: hotel, name: "Ocean Villa King")
    create(:room_type, hotel: hotel, name: "Ocean Villa Twin")

    result = described_class.new(
      hotel: hotel,
      message: "tell me about ocean villa",
      interpretation: interpretation(intent: "room_information", topic: "room_information"),
      conversation_state: conversation_state,
      pause: false
    ).call

    expect(result[:reply_type]).to eq(:ambiguous_room_type)
    expect(result.dig(:extra_context, :result, "error")).to eq("ambiguous_room_type")
  end

  it "returns a room type not found domain result" do
    create(:room_type, hotel: hotel, name: "Executive Suite")

    result = described_class.new(
      hotel: hotel,
      message: "tell me about moon base room",
      interpretation: interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => "Moon Base Room" }),
      conversation_state: conversation_state,
      pause: false
    ).call

    expect(result[:reply_type]).to eq(:room_type_not_found)
    expect(result.dig(:extra_context, :result, "error")).to eq("room_type_not_found")
  end

  it "does not suspend an active booking when pause is false" do
    result = described_class.new(
      hotel: hotel,
      message: "tell me about the hotel",
      interpretation: interpretation(intent: "hotel_information", topic: "general_hotel_info"),
      conversation_state: conversation_state,
      pause: false
    ).call

    expect(result.dig(:slots_payload, "booking_task", "status")).to eq("waiting_for_confirmation")
    expect(result.dig(:slots_payload, "booking_task", "suspended")).to be(false)
    expect(result[:pending_question]).to be_nil
  end

  it "returns a domain result and suspends active booking for information" do
    result = described_class.new(
      hotel: hotel,
      message: "what time is check in?",
      interpretation: interpretation(intent: "hotel_policy", topic: "hotel_policy", tool_hints: [ "get_hotel_policy" ]),
      conversation_state: conversation_state,
      pause: true
    ).call

    expect(result[:reply_type]).to eq(:hotel_policy)
    expect(result[:active_topic]).to eq("hotel_policy")
    expect(result[:active_flow]).to eq("hotel_policy")
    expect(result[:pending_question]).to be_nil
    expect(result[:action_name]).to be_nil
    expect(result.dig(:extra_context, :result, "check_in_time")).to eq("3:00 PM")

    payload = result[:slots_payload]
    expect(payload.dig("booking_task", "status")).to eq("suspended")
    expect(payload.dig("booking_task", "pending_question")).to eq("confirm_selection")
    expect(payload.dig("information_task", "intent")).to eq("hotel_policy")
    expect(payload.dig("information_task", "last_question")).to eq("what time is check in?")
    expect(payload).not_to have_key("active")
    expect(payload).not_to have_key("paused_flows")
  end

  it "suspends the current merged booking branch when provided" do
    empty_state = create(:prospect_conversation_state, prospect: prospect, slots_payload: {})
    active_branch = {
      "branch_id" => "branch-2",
      "target_month" => 9,
      "target_year" => 2026,
      "month_segment" => "early",
      "room_count" => 1
    }

    result = described_class.new(
      hotel: hotel,
      message: "early september, what time is check in?",
      interpretation: interpretation(intent: "hotel_policy", topic: "hotel_policy", tool_hints: [ "get_hotel_policy" ]),
      conversation_state: empty_state,
      pause: true,
      active_branch: active_branch
    ).call

    payload = result[:slots_payload]
    expect(payload.dig("booking_task", "status")).to eq("suspended")
    expect(payload.dig("booking_task", "branch", "target_month")).to eq(9)
    expect(payload.dig("booking_task", "branch", "target_year")).to eq(2026)
    expect(payload.dig("booking_task", "branch", "month_segment")).to eq("early")
    expect(payload.dig("information_task", "last_question")).to eq("early september, what time is check in?")
  end

  def interpretation(intent:, topic:, slots: {}, tool_hints: [])
    {
      "intent" => intent,
      "topic" => topic,
      "confidence" => 1.0,
      "slots" => slots,
      "tool_hints" => tool_hints,
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
