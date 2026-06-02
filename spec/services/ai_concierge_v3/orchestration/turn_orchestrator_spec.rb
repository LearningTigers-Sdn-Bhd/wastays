require "rails_helper"

RSpec.describe AiConciergeV3::Orchestration::TurnOrchestrator do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  before do
    create(:property_policy, hotel: hotel)
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([])
  end

  it "asks for duration after a month window is provided" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 8, "target_year" => 2026, "month_segment" => "mid", "days" => 3, "nights" => 2 })
    )

    result = described_class.new(hotel: hotel, message: "mid august", phone: "+60123456789").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many days and nights")
    expect(result.payload[:action_name]).to eq("request_quote")
  end

  it "asks for booking timing when the interpreter invents a month for a vague message" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 5, "target_year" => 2026, "month_segment" => "early", "adults" => 2, "children" => 0 })
    )

    result = described_class.new(hotel: hotel, message: "hello, is there any booking for 2 adults", phone: "+60123456789").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("what dates or month")
    expect(result.payload[:reply_message]).not_to include("May")
  end

  it "answers booking policy phrasing instead of continuing slot collection" do
    hotel.property_policy.update!(check_in_time: "3:00 PM", check_out_time: "11:00 AM")
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "booking_search", topic: "booking_search", slots: {})
    )

    result = described_class.new(hotel: hotel, message: "before that, may i know the booking policy?", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(result.payload[:reply_message]).to include("Here is our hotel policy")
    expect(result.payload[:reply_message]).to include("3:00 PM")
    expect(result.payload[:reply_message]).not_to include("what dates or month")
    expect(state.slots_payload.dig("information_task", "intent")).to eq("hotel_policy")
  end

  it "answers house rules phrasing instead of starting booking when the interpreter returns booking search" do
    doc = create(:hotel_knowledge_document, hotel: hotel, category: "policy", title: "House Rules", embedding_status: "indexed")
    create(:hotel_knowledge_chunk, document: doc, chunk_index: 0, content: "Quiet hours start at 10 PM.")
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "booking_search", topic: "booking_search", slots: {})
    )

    result = described_class.new(hotel: hotel, message: "do you have house rules?", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(result.payload[:reply_message]).to include("Quiet hours start at 10 PM")
    expect(result.payload[:reply_message]).not_to include("what dates or month")
    expect(result.payload[:action_name]).to be_nil
    expect(state.slots_payload.dig("information_task", "intent")).to eq("hotel_policy")
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")
  end

  it "answers transportation as hotel knowledge instead of starting booking when the interpreter returns booking search" do
    stub_knowledge_search(
      "general_info" => [
        knowledge_match("Airport transportation is available by request.", category: "general_info")
      ]
    )
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "booking_search", topic: "booking_search", slots: {})
    )

    result = described_class.new(hotel: hotel, message: "may i know if the hotel provide transportation", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(result.payload[:reply_message]).to include("Airport transportation is available by request")
    expect(result.payload[:reply_message]).not_to include("what dates or month")
    expect(result.payload[:action_name]).to be_nil
    expect(state.slots_payload.dig("information_task", "intent")).to eq("hotel_information")
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")
  end

  it "answers parking from faq when routed through general hotel information" do
    stub_knowledge_search(
      "general_info" => [],
      "faq,general_info,policy" => [
        knowledge_match("Parking is complimentary for hotel guests.", category: "faq")
      ]
    )
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "booking_search", topic: "booking_search", slots: {})
    )

    result = described_class.new(hotel: hotel, message: "is parking available there?", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(result.payload[:reply_message]).to include("Parking is complimentary for hotel guests")
    expect(result.payload[:reply_message]).not_to include("what dates or month")
    expect(result.payload[:action_name]).to be_nil
    expect(state.slots_payload.dig("information_task", "intent")).to eq("hotel_information")
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")
  end

  it "keeps room availability questions in the booking flow" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "booking_search", topic: "booking_search", slots: { "target_month" => 7, "target_year" => 2026 })
    )

    result = described_class.new(hotel: hotel, message: "do you have rooms available in july?", phone: "+60123456789").call

    expect(result.payload[:reply_message]).to include("exact check-in date")
    expect(result.payload[:action_name]).to eq("request_quote")
  end

  it "does not end the conversation on a greeting" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "greeting", conversation_signals: { "end_conversation" => true })
    )

    result = described_class.new(hotel: hotel, message: "hello", phone: "+60123456789").call

    expect(result.payload[:reply_message]).to include("Hello, welcome to")
    expect(result.payload[:reply_message]).not_to include("No problem, please let me know if you need anything.")
  end

  it "returns an internal server error when orchestration fails unexpectedly" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_raise(StandardError, "boom")

    result = described_class.new(hotel: hotel, message: "hello", phone: "+60123456789").call

    expect(result).not_to be_success
    expect(result.status).to eq(:internal_server_error)
    expect(result.error).to eq("AI Concierge is temporarily unavailable.")
  end

  it "ends the conversation when the user repeats an explicit end request during a booking" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 8 })
    )
    described_class.new(hotel: hotel, message: "book in august", phone: "+60123456789").call

    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "greeting")
    )

    prompt = described_class.new(hotel: hotel, message: "stop", phone: "+60123456789").call
    expect(prompt.payload[:reply_message]).to include("do you want to cancel")

    finish = described_class.new(hotel: hotel, message: "stop", phone: "+60123456789").call
    expect(finish.payload[:reply_message]).to eq("No problem, please let me know if you need anything.")
  end

  it "preserves people as a split clarification when the interpreter invents adults" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call) do |agent|
      current_message = agent.instance_variable_get(:@message)

      if current_message == "can i book for early june? for 2 people"
        interpretation(slots: { "target_month" => 6, "target_year" => 2026, "month_segment" => "early", "party_size_total" => 2, "adults" => 2 })
      else
        interpretation(slots: { "days" => 2, "nights" => 1 })
      end
    end

    result = described_class.new(hotel: hotel, message: "can i book for early june? for 2 people", phone: "+60123456789").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many days and nights")

    follow_up = described_class.new(hotel: hotel, message: "2 days 1 night", phone: "+60123456789").call
    expect(follow_up.payload[:reply_message]).to include("For 2 people")
  end

  it "asks for guest count when stay duration is provided without people total" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 6, "target_year" => 2026, "month_segment" => "early", "days" => 4, "nights" => 3 })
    )

    result = described_class.new(hotel: hotel, message: "early june for 4 days", phone: "+60123456789").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many guests")
  end

  it "removes party_size_total if it is not explicitly in the message" do
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "party_size_total" => 1 })
    )

    result = described_class.new(hotel: hotel, message: "i want to book", phone: "+60123456789").call

    # TransitionPolicy should ask for timing first, but we want to check that party_size_total didn't leak into state
    # Actually, let's check the persisted state or the response payload if possible.
    # The payload doesn't include the active branch directly, but we can verify the follow-up message.

    # If party_size_total was 1, it would ask for adult/child split or timing.
    # If party_size_total is nil, it will ask for timing.
    expect(result.payload[:reply_message]).to include("what dates or month")

    # Let's verify that it doesn't ask "For 1 people" in the next turn if we give it a month window.
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 7, "target_year" => 2026, "month_segment" => "early" })
    )

    follow_up = described_class.new(hotel: hotel, message: "early july", phone: "+60123456789").call
    expect(follow_up.payload[:reply_message]).to include("How many days and nights")

    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "days" => 3, "nights" => 2 })
    )

    days_reply = described_class.new(hotel: hotel, message: "3 days", phone: "+60123456789").call
    expect(days_reply.payload[:reply_message]).to include("How many guests") # Not "For 1 people"
  end

  it "confirms before ending the conversation and reactivates cleanly" do
    # 1. Start a booking flow
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: { "target_month" => 7, "target_year" => 2026, "party_size_total" => 1 })
    )
    described_class.new(hotel: hotel, message: "book for 1 person in july", phone: "+60123456789").call

    # 2. Ask to end the conversation
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "greeting", slots: {})
    )
    end_reply = described_class.new(hotel: hotel, message: "nevermind", phone: "+60123456789").call
    expect(end_reply.payload[:reply_message]).to eq("Dear guest, do you want to cancel your booking quotation attempt?")

    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload
    expect(state.pending_question).to eq("confirm_to_end_conversation")

    # 3. Decline the end prompt and keep the flow alive
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "confirmation", slots: { "confirmation" => "no" })
    )
    no_reply = described_class.new(hotel: hotel, message: "no", phone: "+60123456789").call
    expect(no_reply.payload[:reply_message]).to eq("No problem, please let me know if you need anything.")

    # 4. Ask again and confirm the end prompt, then reactivate with a greeting/booking request
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "greeting", slots: {})
    )
    second_prompt = described_class.new(hotel: hotel, message: "nevermind", phone: "+60123456789").call
    expect(second_prompt.payload[:reply_message]).to eq("Dear guest, do you want to cancel your booking quotation attempt?")

    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "confirmation", slots: { "confirmation" => "yes" })
    )
    yes_reply = described_class.new(hotel: hotel, message: "yes", phone: "+60123456789").call
    expect(yes_reply.payload[:reply_message]).to include("let me know if you need anything")

    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(slots: {}) # No slots, just "can i book"
    )
    reactivation_reply = described_class.new(hotel: hotel, message: "hello, can i make booking", phone: "+60123456789").call

    # It should ask for timing because the previous branch (with July) was archived
    expect(reactivation_reply.payload[:reply_message]).to include("what dates or month")
  end

  it "keeps a suspended confirmation through information turns and resumes on yes" do
    prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")
    room_type = create(:room_type, hotel: hotel, name: "Deluxe Room")
    selected_option = {
      "selection_id" => "sel_1",
      "room_type_id" => room_type.id,
      "room_type_name" => "Deluxe Room",
      "check_in" => "2026-08-03",
      "check_out" => "2026-08-05",
      "adults" => 2,
      "children" => 0,
      "room_count" => 1,
      "currency" => "MYR",
      "total_price" => 500.0
    }
    branch = {
      "branch_id" => "branch-1",
      "target_month" => 8,
      "target_year" => 2026,
      "suggested_options" => [ { "room_type_name" => "Deluxe Room", "options" => [ selected_option.merge("position" => 1) ] } ],
      "suggestion_set_version" => 1,
      "confirmation_candidate" => selected_option,
      "selected_option" => selected_option
    }
    slots_payload = AiConciergeV3::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")
    create(:prospect_conversation_state, prospect: prospect, pending_question: "confirm_selection", slots_payload: slots_payload)

    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call) do |agent|
      if agent.instance_variable_get(:@message) == "what time is check in?"
        interpretation(intent: "hotel_policy", topic: "hotel_policy", slots: {}, tool_hints: [ "get_hotel_policy" ])
      else
        interpretation(intent: "confirmation", slots: { "confirmation" => "yes" }, tool_hints: [ "generate_booking_url" ])
      end
    end

    fake_generate_tool = Class.new do
      def initialize(*)
      end

      def call
        {
          "success" => true,
          "booking_url" => "https://example.test/quotes/token",
          "total_amount" => 500.0,
          "currency" => "MYR",
          "expires_at" => 1.hour.from_now.iso8601,
          "quote_token" => "token"
        }
      end
    end
    original_fetch = AiConciergeV3::Tools::ToolRegistry.instance_method(:fetch)
    allow_any_instance_of(AiConciergeV3::Tools::ToolRegistry).to receive(:fetch) do |registry, name|
      name == "generate_booking_url" ? fake_generate_tool : original_fetch.bind_call(registry, name)
    end

    info_reply = described_class.new(hotel: hotel, message: "what time is check in?", phone: "+60123456789").call
    state_after_info = prospect.reload.prospect_conversation_state

    expect(info_reply.payload[:reply_message]).to be_present
    expect(state_after_info.slots_payload.dig("booking_task", "status")).to eq("suspended")
    expect(state_after_info.slots_payload.dig("booking_task", "pending_question")).to eq("confirm_selection")
    expect(state_after_info.slots_payload).not_to have_key("active")
    expect(state_after_info.slots_payload).not_to have_key("paused_flows")

    confirm_reply = described_class.new(hotel: hotel, message: "yes", phone: "+60123456789").call

    expect(confirm_reply.payload[:reply_message]).to include("Quotation link")
    expect(confirm_reply.payload[:reply_message]).to include("https://example.test/quotes/token")
  end

  it "resumes slot collection with a date after a hotel information interruption" do
    hotel.update!(amenities: [ "swimming_pool" ])

    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call) do |agent|
      case agent.instance_variable_get(:@message)
      when "i would like to make reservation on next month"
        interpretation(slots: { "target_month" => 6, "target_year" => 2026 })
      when "may i know is there swimming pool"
        interpretation(intent: "hotel_information", topic: "general_hotel_info", slots: {}, tool_hints: [ "get_general_hotel_info" ])
      else
        interpretation(intent: "confirmation", slots: { "confirmation" => "yes" })
      end
    end

    first_reply = described_class.new(hotel: hotel, message: "i would like to make reservation on next month", phone: "+60123456789").call
    info_reply = described_class.new(hotel: hotel, message: "may i know is there swimming pool", phone: "+60123456789").call
    resume_reply = described_class.new(hotel: hotel, message: "ok, i want to book on 23 june", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(first_reply.payload[:reply_message]).to include("exact check-in date")
    expect(first_reply.payload[:action_name]).to eq("request_quote")
    expect(info_reply.payload[:reply_message]).to include("Swimming Pool")
    expect(info_reply.payload[:reply_message]).not_to include("couldn't match")
    expect(resume_reply.payload[:reply_message]).to eq("How many days and nights will you be staying?")
    expect(resume_reply.payload[:action_name]).to eq("request_quote")
    expect(state.slots_payload.dig("booking_task", "status")).to eq("collecting_slots")
    expect(state.slots_payload.dig("booking_task", "pending_question")).to eq("duration")
    expect(state.slots_payload.dig("booking_task", "branch", "check_in")).to eq("2026-06-23")
  end

  it "suspends active booking for guarded hotel knowledge and resumes afterward" do
    stub_knowledge_search(
      "general_info" => [],
      "faq,general_info,policy" => [
        knowledge_match("Parking is available near the lobby.", category: "faq")
      ]
    )

    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call) do |agent|
      case agent.instance_variable_get(:@message)
      when "i would like to make reservation on next month"
        interpretation(slots: { "target_month" => 6, "target_year" => 2026 })
      when "is parking available there?"
        interpretation(intent: "booking_search", topic: "booking_search", slots: {})
      else
        interpretation(intent: "booking_search", slots: { "check_in" => "2026-06-23" })
      end
    end

    first_reply = described_class.new(hotel: hotel, message: "i would like to make reservation on next month", phone: "+60123456789").call
    info_reply = described_class.new(hotel: hotel, message: "is parking available there?", phone: "+60123456789").call
    state_after_info = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload
    resume_reply = described_class.new(hotel: hotel, message: "ok, i want to book on 23 june", phone: "+60123456789").call
    state_after_resume = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(first_reply.payload[:reply_message]).to include("exact check-in date")
    expect(info_reply.payload[:reply_message]).to include("Parking is available near the lobby")
    expect(state_after_info.slots_payload.dig("booking_task", "status")).to eq("suspended")
    expect(state_after_info.slots_payload.dig("booking_task", "pending_question")).to eq("specific_timing")
    expect(resume_reply.payload[:reply_message]).to eq("How many days and nights will you be staying?")
    expect(state_after_resume.slots_payload.dig("booking_task", "status")).to eq("collecting_slots")
    expect(state_after_resume.slots_payload.dig("booking_task", "branch", "check_in")).to eq("2026-06-23")
  end

  it "preserves resumed room selection clarifications" do
    prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")
    room_type = create(:room_type, hotel: hotel, name: "Deluxe Room")
    option_one = {
      "selection_id" => "sel_1",
      "room_type_id" => room_type.id,
      "room_type_name" => "Deluxe Room",
      "check_in" => "2026-08-03",
      "check_out" => "2026-08-05",
      "adults" => 2,
      "children" => 0,
      "room_count" => 1,
      "currency" => "MYR",
      "total_price" => 500.0,
      "position" => 1
    }
    option_two = option_one.merge(
      "selection_id" => "sel_2",
      "check_in" => "2026-08-06",
      "check_out" => "2026-08-08",
      "total_price" => 520.0,
      "position" => 2
    )
    branch = {
      "branch_id" => "branch-1",
      "target_month" => 8,
      "target_year" => 2026,
      "suggested_options" => [ { "room_type_name" => "Deluxe Room", "options" => [ option_one, option_two ] } ],
      "suggestion_set_version" => 1
    }
    active_payload = AiConciergeV3::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "select_option")
    suspended_payload = AiConciergeV3::State::ConversationTaskManager.new(slots_payload: active_payload).suspend_booking_for_information(intent: "hotel_policy", topic: "hotel_policy", pending_question: "select_option")
    create(:prospect_conversation_state, prospect: prospect, pending_question: nil, slots_payload: suspended_payload)

    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "booking_search", slots: {})
    )

    result = described_class.new(hotel: hotel, message: "Deluxe Room", phone: "+60123456789").call
    state = prospect.reload.prospect_conversation_state

    expect(result.payload[:reply_message]).to include("I found multiple options under Deluxe Room")
    expect(result.payload[:reply_message]).to include("Please tell me the option number")
    expect(state.slots_payload.dig("booking_task", "branch", "pending_selection", "room_type_name")).to eq("Deluxe Room")
    expect(state.slots_payload.dig("booking_task", "pending_question")).to eq("select_option")
  end

  it "answers hotel amenities after a completed quote without treating it as room information" do
    hotel.update!(amenities: [ "wifi", "swimming_pool" ])
    prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")
    branch = {
      "branch_id" => "branch-1",
      "selected_option" => { "selection_id" => "sel_1", "room_type_name" => "Deluxe Room" }
    }
    payload = AiConciergeV3::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: nil, status: "completed")
    payload = AiConciergeV3::State::ConversationTaskManager.new(slots_payload: payload).archive_completed_booking
    create(:prospect_conversation_state, prospect: prospect, flow_status: "ended", slots_payload: payload)

    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => nil }, tool_hints: [ "get_room_type_details" ])
    )

    result = described_class.new(hotel: hotel, message: "available facilities?", phone: "+60123456789").call
    state = prospect.reload.prospect_conversation_state

    expect(result.payload[:reply_message]).to include("Hotel amenities: Free WiFi, Swimming Pool")
    expect(result.payload[:reply_message]).not_to include("I couldn't match that room type")
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")
    expect(state.slots_payload["completed_booking_branches"]).to be_present
  end

  it "keeps named room amenity questions on room information" do
    create(:room_type, hotel: hotel, name: "Deluxe Room", amenities: [ "wifi", "ac" ])
    allow_any_instance_of(AiConciergeV3::Agents::InterpreterAgent).to receive(:call).and_return(
      interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => "Deluxe Room" }, tool_hints: [ "get_room_type_details" ])
    )

    result = described_class.new(hotel: hotel, message: "what amenities does deluxe room have?", phone: "+60123456789").call

    expect(result.payload[:reply_message]).to include("Here are the details for Deluxe Room")
    expect(result.payload[:reply_message]).to include("Amenities: Free WiFi, Air Conditioning")
  end

  def interpretation(intent: "booking_search", topic: "booking_search", slots: {}, tool_hints: [ "search_booking_options" ], conversation_signals: {})
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
      }.merge(conversation_signals)
    }
  end

  def stub_knowledge_search(results)
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call) do |service|
      categories = Array(service.instance_variable_get(:@categories)).map(&:to_s).sort.join(",")
      results.fetch(categories, [])
    end
  end

  def knowledge_match(content, category:, distance: 0.12)
    {
      "content" => content,
      "document_title" => category.titleize,
      "category" => category,
      "language" => "en",
      "version" => 1,
      "chunk_index" => 0,
      "distance" => distance
    }
  end
end
