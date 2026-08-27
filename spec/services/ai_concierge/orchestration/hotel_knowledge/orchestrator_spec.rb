require "rails_helper"

RSpec.describe AiConcierge::Orchestration::HotelKnowledge::Orchestrator do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel, phone_number: "+60123456789") }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect, pending_question: "confirm_selection", slots_payload: slots_payload) }
  let(:idle_conversation_state) do
    create(:prospect_conversation_state, prospect: create(:prospect, hotel: hotel), slots_payload: {})
  end
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
    AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")
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
      conversation_state: idle_conversation_state,
      pause: false
    ).call

    expect(result[:reply_type]).to eq(:general_hotel_info)
    expect(result[:active_topic]).to be_nil
    expect(result[:active_flow]).to be_nil
    expect(result.dig(:extra_context, :result, "name")).to eq(hotel.name)
    expect(result.dig(:extra_context, :result, "amenities")).to be_present
    expect(result.dig(:slots_payload, "booking_task", "status")).to eq("idle")
    expect(result.dig(:slots_payload, "information_task", "intent")).to eq("hotel_information")
    expect(result.dig(:extra_context, :result, "answer"))
      .to end_with("Would you like me to help you find a room for your travel dates?")
    expect(result.dig(:slots_payload, "sales_task", "last_optional_action")).to eq("offer_booking_help")
    expect(result.next_action.kind).to eq("offer_booking_help")
  end

  it "returns a hotel faq domain result" do
    doc = create(:hotel_knowledge_document, hotel: hotel, category: "faq", title: "General", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: doc, chunk_index: 0, content: "Q: Breakfast?\nA: From 7 AM.")

    result = described_class.new(
      hotel: hotel,
      message: "do you have an faq?",
      interpretation: interpretation(intent: "hotel_information", topic: "hotel_faq"),
      conversation_state: idle_conversation_state,
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
      conversation_state: idle_conversation_state,
      pause: false
    ).call

    expect(result[:reply_type]).to eq(:nearby_attractions)
    expect(result.dig(:extra_context, :result, "attractions").first["name"]).to eq("Sky Bridge")
    expect(result.dig(:extra_context, :result, "answer")).to include("- Sky Bridge: Scenic landmark.")
    expect(result.dig(:extra_context, :result, "answer"))
      .to end_with("Would you like me to help you find a room for your travel dates?")
  end

  it "returns a room information success domain result" do
    room_type = create(:room_type, hotel: hotel, name: "Executive Suite", description: "Large suite.", amenities: %w[wifi balcony])

    result = described_class.new(
      hotel: hotel,
      message: "tell me about the executive suite",
      interpretation: interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => "Executive Suite" }),
      conversation_state: idle_conversation_state,
      pause: false
    ).call

    expect(result[:reply_type]).to eq(:room_type_details)
    expect(result.dig(:extra_context, :result, "matched_room_type_id")).to eq(room_type.id)
    expect(result.dig(:extra_context, :result, "amenities")).to include("Free WiFi", "Balcony / Terrace")
    factual_answer, action = result.dig(:extra_context, :result, "answer").split("\n\n")
    expect(factual_answer.split(/(?<=[.!?])\s+/).size).to be <= 2
    expect(action).to eq("Would you like me to check prices for this room for your travel dates?")
    expect(result.next_action.kind).to eq("offer_price_search")
  end

  it "uses conditional booking copy after a restriction" do
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([
      {
        "content" => "Pets are not allowed.",
        "document_title" => "Pets",
        "category" => "policy",
        "distance" => 0.1
      }
    ])

    result = described_class.new(
      hotel: hotel,
      message: "can I bring a pet?",
      interpretation: interpretation(intent: "hotel_policy", topic: "hotel_policy"),
      conversation_state: idle_conversation_state,
      pause: false
    ).call

    expect(result.dig(:extra_context, :result, "answer"))
      .to eq("Pets are not allowed.\n\nIf this policy works for you, I can help you find a room for your travel dates.")
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
    expect(result.dig(:extra_context, :result, "answer")).to include("Ocean Villa King", "Ocean Villa Twin", "Which one")
    expect(result.dig(:slots_payload, "information_task", "status")).to eq("waiting_for_guest")
    expect(result.dig(:slots_payload, "information_task", "pending_question")).to eq("room_type_choice")
    expect(result.dig(:slots_payload, "information_task", "context", "choices"))
      .to contain_exactly("Ocean Villa King", "Ocean Villa Twin")
    expect(result.next_action).to be_none
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
    expect(result.dig(:extra_context, :result, "answer")).to eq("I could not match that room type. Please send the room type name.")
    expect(result.dig(:slots_payload, "information_task", "pending_question")).to eq("room_type_name")
    expect(result.next_action).to be_none
  end

  it "records an opening-hours clarification as an open information question" do
    result = described_class.new(
      hotel: hotel,
      message: "what hour you start open",
      interpretation: interpretation(intent: "hotel_information", topic: "general_hotel_info").merge("scope" => "specific"),
      conversation_state: conversation_state,
      pause: false
    ).call

    expect(result.dig(:extra_context, :result, "answer"))
      .to eq("Do you mean the hotel check-in time or the opening hours of a facility?")
    expect(result.dig(:slots_payload, "information_task", "pending_question")).to eq("opening_hours_subject")
    expect(result.dig(:slots_payload, "information_task", "context", "choices")).to eq([ "check-in", "facility" ])
  end

  it "gives one front-desk action when attraction information is missing" do
    result = described_class.new(
      hotel: hotel,
      message: "what attractions are nearby?",
      interpretation: interpretation(intent: "nearby_attractions", topic: "nearby_attractions"),
      conversation_state: idle_conversation_state,
      pause: false
    ).call

    expect(result.dig(:extra_context, :result, "answer"))
      .to eq("The hotel has not listed nearby attractions yet.\n\nPlease ask the front desk for local recommendations.")
    expect(result.dig(:extra_context, :result, "answer").scan(/front desk/i).size).to eq(1)
    expect(result.next_action.kind).to eq("offer_front_desk")
  end

  it "keeps front-desk guidance without consuming optional-offer suppression" do
    offered = AiConcierge::State::ConversationTaskManager
      .new(slots_payload: {})
      .record_optional_sales_offer("offer_booking_help")
    declined = AiConcierge::State::ConversationTaskManager.new(slots_payload: offered).decline_optional_sales_offer
    idle_conversation_state.update!(slots_payload: declined)

    result = described_class.new(
      hotel: hotel,
      message: "what attractions are nearby?",
      interpretation: interpretation(intent: "nearby_attractions", topic: "nearby_attractions"),
      conversation_state: idle_conversation_state,
      pause: false
    ).call

    expect(result.next_action.kind).to eq("offer_front_desk")
    expect(result.dig(:extra_context, :result, "answer")).to start_with("No problem.")
    expect(result.dig(:slots_payload, "sales_task", "suppress_next_optional_offer")).to be(true)
    expect(result.dig(:slots_payload, "sales_task", "refusal_acknowledgment_pending")).to be(false)
  end

  it "suppresses one optional offer and allows the following offer" do
    hotel.update!(amenities: [ Hotel::HOTEL_AMENITIES.first.fetch(:id) ])
    offered = AiConcierge::State::ConversationTaskManager
      .new(slots_payload: {})
      .record_optional_sales_offer("offer_booking_help")
    declined = AiConcierge::State::ConversationTaskManager.new(slots_payload: offered).decline_optional_sales_offer
    suppressed = AiConcierge::State::ConversationTaskManager.new(slots_payload: declined).clear_optional_sales_offer
    idle_conversation_state.update!(slots_payload: suppressed)

    first = described_class.new(
      hotel: hotel,
      message: "what amenities do you have?",
      interpretation: interpretation(intent: "hotel_information", topic: "general_hotel_info"),
      conversation_state: idle_conversation_state,
      pause: false
    ).call

    expect(first.next_action).to be_none
    expect(first.dig(:extra_context, :result, "answer")).not_to include("find a room")
    expect(first.dig(:slots_payload, "sales_task", "suppress_next_optional_offer")).to be(false)

    idle_conversation_state.update!(slots_payload: first.slots_payload)
    second = described_class.new(
      hotel: hotel,
      message: "tell me about the hotel",
      interpretation: interpretation(intent: "hotel_information", topic: "general_hotel_info"),
      conversation_state: idle_conversation_state,
      pause: false
    ).call

    expect(second.next_action.kind).to eq("offer_booking_help")
    expect(second.dig(:extra_context, :result, "answer")).to include("find a room")
  end

  it "acknowledges a refusal before answering a new question" do
    offered = AiConcierge::State::ConversationTaskManager
      .new(slots_payload: {})
      .record_optional_sales_offer("offer_booking_help")
    declined = AiConcierge::State::ConversationTaskManager.new(slots_payload: offered).decline_optional_sales_offer
    idle_conversation_state.update!(slots_payload: declined)

    result = described_class.new(
      hotel: hotel,
      message: "no thanks, what time is check-out?",
      interpretation: interpretation(intent: "hotel_policy", topic: "hotel_policy"),
      conversation_state: idle_conversation_state,
      pause: false
    ).call

    expect(result.dig(:extra_context, :result, "answer")).to eq("No problem. Check-out is by 11:00 AM.")
    expect(result.next_action).to be_none
    expect(result.dig(:slots_payload, "sales_task", "suppress_next_optional_offer")).to be(false)
  end

  it "does not repeat the previous restriction when the guest asks what else" do
    conversation = create(:conversation, hotel: hotel, prospect: prospect)
    create(
      :prospect_message,
      prospect: prospect,
      conversation: conversation,
      direction: "outbound",
      body: "Pets are not allowed."
    )
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([
      {
        "content" => "Pets are not allowed.",
        "document_title" => "Pets",
        "category" => "policy",
        "distance" => 0.1
      }
    ])

    result = described_class.new(
      hotel: hotel,
      message: "what else is restricted?",
      interpretation: interpretation(intent: "hotel_policy", topic: "hotel_policy"),
      conversation_state: conversation_state,
      pause: false
    ).call

    expect(result.dig(:extra_context, :result, "answer"))
      .to eq("I could not find another listed restriction.\n\nWould you like to continue your booking?")
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
    result = nil
    expect {
      result = described_class.new(
        hotel: hotel,
        message: "what time is check in?",
        interpretation: interpretation(intent: "hotel_policy", topic: "hotel_policy", tool_hints: [ "get_hotel_policy" ]),
        conversation_state: conversation_state,
        pause: true
      ).call
    }.to change(HotelKnowledgeDiagnostic, :count).by(1)

    expect(result[:reply_type]).to eq(:hotel_policy)
    expect(result[:active_topic]).to eq("hotel_policy")
    expect(result[:active_flow]).to eq("hotel_policy")
    expect(result[:pending_question]).to be_nil
    expect(result[:action_name]).to be_nil
    expect(result.dig(:extra_context, :result, "check_in_time")).to eq("3:00 PM")
    expect(result.dig(:extra_context, :result, "answer"))
      .to eq("You can check in from 3:00 PM.\n\nWould you like to continue your booking?")
    expect(HotelKnowledgeDiagnostic.last.answer_mode).to eq("structured")

    payload = result[:slots_payload]
    expect(payload.dig("booking_task", "status")).to eq("suspended")
    expect(payload.dig("booking_task", "pending_question")).to eq("confirm_selection")
    expect(payload.dig("information_task", "intent")).to eq("hotel_policy")
    expect(payload.dig("information_task", "last_question")).to eq("what time is check in?")
    expect(payload).not_to have_key("active")
    expect(payload).not_to have_key("paused_flows")
    expect(result.next_action.kind).to eq("resume_booking")
  end

  it "does not suppress booking resumption after a sales refusal" do
    offered = AiConcierge::State::ConversationTaskManager
      .new(slots_payload: slots_payload)
      .record_optional_sales_offer("offer_booking_help")
    declined = AiConcierge::State::ConversationTaskManager.new(slots_payload: offered).decline_optional_sales_offer
    conversation_state.update!(slots_payload: declined)

    result = described_class.new(
      hotel: hotel,
      message: "what time is check in?",
      interpretation: interpretation(intent: "hotel_policy", topic: "hotel_policy"),
      conversation_state: conversation_state,
      pause: true
    ).call

    expect(result.next_action.kind).to eq("resume_booking")
    expect(result.dig(:extra_context, :result, "answer"))
      .to start_with("No problem. You can check in from 3:00 PM.")
    expect(result.dig(:slots_payload, "sales_task", "suppress_next_optional_offer")).to be(true)
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
