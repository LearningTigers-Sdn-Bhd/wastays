require "rails_helper"

RSpec.describe AiConcierge::Orchestration::TurnOrchestrator do
  # Six examples were removed here with InformationIntentGuard and
  # TransitionPolicy. Each one scripted the model choosing wrongly -- a house
  # rules question read as a booking, "available facilities?" routed to a room
  # type, a generic "i want to make booking" landing on a stale branch -- and
  # asserted that the pipeline overruled it afterwards. The loop does not
  # overrule the model; the tool descriptions are what keep it honest, and being
  # wrong here is cheap. What survives is the guard rule that was not cheap:
  # Core::RateQuestion, covered by the intent_guard eval fixtures.
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  before do
    create(:property_policy, hotel: hotel)
    allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([])
    # Every reply now passes the stylist on its way out, including the control
    # replies below that never consult the loop. Passing the template through is
    # what a hotel on the default tone answering in English gets.
    stub_concierge_stylist
  end

  it "serializes a prospect turn with a row lock" do
    prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")
    create(:prospect_conversation_state, prospect: prospect)
    locked = false

    allow_any_instance_of(AiConcierge::Providers::RubyLlmClient).to receive(:chat) do
      expect(locked).to be(true)
      AiConciergeEval::ScriptedChat.new(interpretation: interpretation(intent: "greeting", topic: "general", slots: {}))
    end
    expect_any_instance_of(Prospect).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      locked = true
      original.call(*args, &block)
    ensure
      locked = false
    end

    result = described_class.new(hotel: hotel, message: "hello", prospect_public_id: prospect.public_id).call

    expect(result).to be_success
  end

  it "asks for duration after a month window is provided" do
    script_model("mid august", interpretation(slots: { "target_month" => 8, "target_year" => 2026, "month_segment" => "mid", "days" => 3, "nights" => 2 }))

    result = described_class.new(hotel: hotel, message: "mid august", phone: "+60123456789").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many days and nights")
    expect(result.payload[:action_name]).to eq("request_quote")
  end

  it "asks for booking timing when the interpreter invents a month for a vague message" do
    script_model("hello, is there any booking for 2 adults", interpretation(slots: { "target_month" => 5, "target_year" => 2026, "month_segment" => "early", "adults" => 2, "children" => 0 }))

    result = described_class.new(hotel: hotel, message: "hello, is there any booking for 2 adults", phone: "+60123456789").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("date or month")
    expect(result.payload[:reply_message]).not_to include("May")
  end

  it "keeps room availability questions in the booking flow" do
    script_model("do you have rooms available in july?", interpretation(intent: "booking_search", topic: "booking_search", slots: { "target_month" => 7, "target_year" => 2026 }))

    result = described_class.new(hotel: hotel, message: "do you have rooms available in july?", phone: "+60123456789").call

    expect(result.payload[:reply_message]).to include("exact check-in date")
    expect(result.payload[:action_name]).to eq("request_quote")
  end

  it "starts booking flow for room rate questions without an active booking branch" do
    script_model("what is room rate?", interpretation(message_type: "hotel_info_question", intent: "hotel_information", topic: "general_hotel_info", slots: {}, tool_hints: [ "get_general_hotel_info" ]))

    result = described_class.new(hotel: hotel, message: "what is room rate?", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("room rates depend on the booking dates and room types")
    expect(result.payload[:reply_message]).to include("Which date or month do you plan to arrive for check-in?")
    expect(result.payload[:action_name]).to be_nil
    expect(state.slots_payload.dig("booking_task", "status")).to eq("collecting_slots")
    expect(state.slots_payload.dig("booking_task", "pending_question")).to eq("booking_timing")
    expect(state.slots_payload.dig("booking_task", "purpose")).to eq("price_exploration")
  end

  it "derives duration from a complete date range answer" do
    with_frozen_time Date.new(2026, 6, 3) do
      script_model("i want to make booking", interpretation(intent: "booking_search", topic: "booking_search", slots: {}))

      first_reply = described_class.new(hotel: hotel, message: "i want to make booking", phone: "+60123456789").call
      range_reply = described_class.new(hotel: hotel, message: "16-18 June", phone: "+60123456789").call
      state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

      expect(first_reply.payload[:reply_message]).to include("date or month")
      expect(range_reply.payload[:reply_message]).to include("How many guests")
      expect(state.slots_payload.dig("booking_task", "branch", "check_in")).to eq("2026-06-16")
      expect(state.slots_payload.dig("booking_task", "branch", "check_out")).to eq("2026-06-18")
      expect(state.slots_payload.dig("booking_task", "branch", "nights")).to eq(2)
      expect(state.slots_payload.dig("booking_task", "pending_question")).to eq("guest_count")
    end
  end

  it "asks which month for a monthless date range answer" do
    script_model("i want to make booking", interpretation(intent: "booking_search", topic: "booking_search", slots: {}))

    described_class.new(hotel: hotel, message: "i want to make booking", phone: "+60123456789").call
    range_reply = described_class.new(hotel: hotel, message: "16-18", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(range_reply.payload[:reply_message]).to eq("You said 16-18, but which month?")
    expect(state.slots_payload.dig("booking_task", "branch", "clarification_needed", "type")).to eq("date_range_month")
    expect(state.slots_payload.dig("booking_task", "pending_question")).to eq("date_range_month")
  end

  it "resolves a pending monthless date range with a follow-up month" do
    with_frozen_time Date.new(2026, 6, 3) do
      script_model("i want to make booking", interpretation(intent: "booking_search", topic: "booking_search", slots: {}))

      described_class.new(hotel: hotel, message: "i want to make booking", phone: "+60123456789").call
      described_class.new(hotel: hotel, message: "16-18", phone: "+60123456789").call
      follow_up = described_class.new(hotel: hotel, message: "next month", phone: "+60123456789").call
      state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

      expect(follow_up.payload[:reply_message]).to include("How many guests")
      expect(state.slots_payload.dig("booking_task", "branch", "check_in")).to eq("2026-07-16")
      expect(state.slots_payload.dig("booking_task", "branch", "check_out")).to eq("2026-07-18")
      expect(state.slots_payload.dig("booking_task", "branch", "nights")).to eq(2)
      expect(state.slots_payload.dig("booking_task", "branch", "clarification_needed")).to eq("")
    end
  end

  it "uses this-month timing instead of stale no-options month context" do
    with_frozen_time Date.new(2026, 6, 3) do
      prospect = create(:prospect, hotel: hotel)
      branch = {
        "target_month" => 7,
        "target_year" => 2026,
        "month_segment" => "late",
        "days" => 4,
        "nights" => 3,
        "party_size_total" => 5,
        "adults" => 5,
        "children" => 0
      }
      slots_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "booking_timing")
      create(:prospect_conversation_state, prospect: prospect, pending_question: "booking_timing", slots_payload: slots_payload)

      script_model("late this month have?", interpretation(intent: "booking_search", topic: "booking_search", slots: {}))

      result = described_class.new(hotel: hotel, message: "late this month have?", prospect_public_id: prospect.public_id).call
      state = prospect.prospect_conversation_state.reload

      expect(result.payload[:reply_message]).to include("late June 2026")
      expect(result.payload[:reply_message]).not_to include("late July 2026")
      expect(state.slots_payload.dig("booking_task", "branch", "target_month")).to eq(6)
      expect(state.slots_payload.dig("booking_task", "branch", "month_segment")).to eq("late")
    end
  end

  it "asks for a timing segment when this-month request omits early mid or late" do
    with_frozen_time Date.new(2026, 6, 3) do
      prospect = create(:prospect, hotel: hotel)
      branch = {
        "target_month" => 7,
        "target_year" => 2026,
        "month_segment" => "late",
        "days" => 4,
        "nights" => 3,
        "party_size_total" => 5,
        "adults" => 5,
        "children" => 0
      }
      slots_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "booking_timing")
      create(:prospect_conversation_state, prospect: prospect, pending_question: "booking_timing", slots_payload: slots_payload)

      script_model("nice, can i book for this month?", interpretation(intent: "booking_search", topic: "booking_search", slots: {}))

      result = described_class.new(hotel: hotel, message: "nice, can i book for this month?", prospect_public_id: prospect.public_id).call
      state = prospect.prospect_conversation_state.reload

      expect(result.payload[:reply_message]).to include("exact check-in date or assumption range")
      expect(result.payload[:reply_message]).to include("June 2026")
      expect(result.payload[:reply_message]).not_to include("Sorry, I couldn't find any rooms")
      expect(state.slots_payload.dig("booking_task", "branch", "target_month")).to eq(6)
      expect(state.slots_payload.dig("booking_task", "branch", "month_segment")).to eq("")
      expect(state.slots_payload.dig("booking_task", "pending_question")).to eq("specific_timing")
    end
  end

  it "answers an idle greeting without consulting the agent loop or starting a booking" do
    expect(AiConcierge::Orchestration::AgentLoop::RunTurn).not_to receive(:new)

    result = described_class.new(hotel: hotel, message: "hello", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(result.payload[:reply_message]).to eq(
      "Hello! Welcome to #{hotel.name}. I can help you find the right stay, check prices, " \
        "answer hotel questions, or access an existing booking. What can I help you with today?"
    )
    expect(result.payload[:action_name]).to be_nil
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")
    expect(state.slots_payload.dig("booking_task", "pending_question")).to be_nil
    expect(state.pending_question).to be_nil
  end

  it "keeps a pending secure booking lookup ahead of greetings and the agent loop" do
    prospect = create(:prospect, hotel: hotel, phone_number: nil)
    conversation = create(:conversation, hotel: hotel, prospect: prospect, channel: "web")
    manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: {})
    create(
      :prospect_conversation_state,
      prospect: prospect,
      slots_payload: manager.request_existing_booking_code,
      active_topic: "existing_booking",
      active_flow: "existing_booking",
      pending_question: "confirmation_code"
    )
    expect(AiConcierge::Orchestration::AgentLoop::RunTurn).not_to receive(:new)

    result = described_class.new(
      hotel: hotel,
      message: "hello",
      prospect_public_id: prospect.public_id,
      channel: conversation.channel
    ).call

      expect(result.payload[:reply_message]).to include("Enter your booking confirmation code")
  end

  it "offers a portal link before asking an anonymous guest for a confirmation code" do
    prospect = create(:prospect, hotel: hotel, phone_number: nil)
    conversation = create(:conversation, hotel: hotel, prospect: prospect, channel: "web")
    expect(AiConcierge::Orchestration::AgentLoop::RunTurn).not_to receive(:new)

    result = described_class.new(
      hotel: hotel,
      message: "I have an existing booking",
      prospect_public_id: prospect.public_id,
      channel: conversation.channel
    ).call

    expect(result.payload[:reply_message]).to include("Guest Portal", "secure login link")
    expect(prospect.prospect_conversation_state.reload.slots_payload.dig("existing_booking_task", "status"))
      .to eq("portal_offered")
  end

  it "returns an internal server error when orchestration fails unexpectedly" do
    allow_any_instance_of(AiConcierge::Providers::RubyLlmClient).to receive(:chat).and_raise(StandardError, "boom")

    result = described_class.new(hotel: hotel, message: "Can you help me?", phone: "+60123456789").call

    expect(result).not_to be_success
    expect(result.status).to eq(:internal_server_error)
    expect(result.error).to eq("AI Concierge is temporarily unavailable.")
  end

  it "force ends wait-time control messages before consulting the model" do
    prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")
    create(:prospect_conversation_state, prospect: prospect)
    expect_any_instance_of(AiConcierge::Providers::RubyLlmClient).not_to receive(:chat)

    result = described_class.new(hotel: hotel, message: "codename: wait-time-end", phone: "+60123456789").call
    state = prospect.prospect_conversation_state.reload

    expect(result).to be_success
    expect(result.payload[:reply_message]).to eq("Thank you for reaching out. Please come back again.")
    expect(state.flow_status).to eq("ended")
    expect(state.slots_payload.dig("conversation", "end_reason")).to eq("wait_time_end")
  end

  it "force ends wait-time control messages with booking-specific copy" do
    prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")
    branch = AiConcierge::State::SlotMerger.empty_branch.merge("target_month" => 8)
    payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "booking_timing")
    create(:prospect_conversation_state, prospect: prospect, active_flow: "booking_search", slots_payload: payload)
    expect_any_instance_of(AiConcierge::Providers::RubyLlmClient).not_to receive(:chat)

    result = described_class.new(hotel: hotel, message: "codename: wait-time-end", phone: "+60123456789").call
    state = prospect.prospect_conversation_state.reload

    expect(result.payload[:reply_message]).to eq("It seems you are no longer making a booking quotation. Thank you for reaching out. Please come back again.")
    expect(state.flow_status).to eq("ended")
    expect(state.active_flow).to be_nil
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")
    expect(state.slots_payload.dig("conversation", "end_reason")).to eq("wait_time_end")
  end

  it "prioritizes wait-time control messages over max-turn handling" do
    prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")
    slots_payload = { "conversation" => { "turn_count" => described_class::MAX_TURNS } }
    create(:prospect_conversation_state, prospect: prospect, slots_payload: slots_payload)
    expect_any_instance_of(AiConcierge::Providers::RubyLlmClient).not_to receive(:chat)

    result = described_class.new(hotel: hotel, message: "codename: wait-time-end", phone: "+60123456789").call
    state = prospect.prospect_conversation_state.reload

    expect(result.payload[:reply_message]).to eq("Thank you for reaching out. Please come back again.")
    expect(result.payload[:needs_human_support]).to be(false)
    expect(state.slots_payload.dig("conversation", "end_reason")).to eq("wait_time_end")
  end

  it "ends the conversation when the user repeats an explicit end request during a booking" do
    script_model("book in august", interpretation(slots: { "target_month" => 8 }))
    described_class.new(hotel: hotel, message: "book in august", phone: "+60123456789").call

    script_model("stop", interpretation(intent: "greeting"))

    prompt = described_class.new(hotel: hotel, message: "stop", phone: "+60123456789").call
    expect(prompt.payload[:reply_message]).to eq("Your booking isn't finished yet. Would you like to end this chat? Please reply *Yes* to end, or *No* to carry on.")

    finish = described_class.new(hotel: hotel, message: "stop", phone: "+60123456789").call
    expect(finish.payload[:reply_message]).to eq("Thank you for chatting with us. Message us any time.")
  end

  it "preserves people as a split clarification when the interpreter invents adults" do
    script_messages(
      "can i book for early june? for 2 people" =>
        interpretation(slots: { "target_month" => 6, "target_year" => 2026, "month_segment" => "early", "party_size_total" => 2, "adults" => 2 })
    )

    result = described_class.new(hotel: hotel, message: "can i book for early june? for 2 people", phone: "+60123456789").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many days and nights")

    follow_up = described_class.new(hotel: hotel, message: "2 days 1 night", phone: "+60123456789").call
    expect(follow_up.payload[:reply_message]).to include("For 2 people")
  end

  it "asks for guest count when stay duration is provided without people total" do
    script_model("early june for 4 days", interpretation(slots: { "target_month" => 6, "target_year" => 2026, "month_segment" => "early", "days" => 4, "nights" => 3 }))

    result = described_class.new(hotel: hotel, message: "early june for 4 days", phone: "+60123456789").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to include("How many guests")
  end

  it "removes party_size_total if it is not explicitly in the message" do
    script_model("i want to book", interpretation(slots: { "party_size_total" => 1 }))

    result = described_class.new(hotel: hotel, message: "i want to book", phone: "+60123456789").call

    # TransitionPolicy should ask for timing first, but we want to check that party_size_total didn't leak into state
    # Actually, let's check the persisted state or the response payload if possible.
    # The payload doesn't include the active branch directly, but we can verify the follow-up message.

    # If party_size_total was 1, it would ask for adult/child split or timing.
    # If party_size_total is nil, it will ask for timing.
    expect(result.payload[:reply_message]).to include("date or month")

    # Let's verify that it doesn't ask "For 1 people" in the next turn if we give it a month window.
    script_model("early july", interpretation(slots: { "target_month" => 7, "target_year" => 2026, "month_segment" => "early" }))

    follow_up = described_class.new(hotel: hotel, message: "early july", phone: "+60123456789").call
    expect(follow_up.payload[:reply_message]).to include("How many days and nights")

    script_model("3 days", interpretation(slots: { "days" => 3, "nights" => 2 }))

    days_reply = described_class.new(hotel: hotel, message: "3 days", phone: "+60123456789").call
    expect(days_reply.payload[:reply_message]).to include("How many guests") # Not "For 1 people"
  end

  it "confirms before ending the conversation and reactivates cleanly" do
    # 1. Start a booking flow
    script_model("book for 1 person in july", interpretation(slots: { "target_month" => 7, "target_year" => 2026, "party_size_total" => 1 }))
    described_class.new(hotel: hotel, message: "book for 1 person in july", phone: "+60123456789").call

    # 2. Ask to end the conversation
    script_model("nevermind", interpretation(intent: "greeting", slots: {}))
    end_reply = described_class.new(hotel: hotel, message: "nevermind", phone: "+60123456789").call
    expect(end_reply.payload[:reply_message]).to eq("Your booking isn't finished yet. Would you like to end this chat? Please reply *Yes* to end, or *No* to carry on.")

    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload
    expect(state.pending_question).to eq("confirm_to_end_conversation")

    # 3. Decline the end prompt and keep the flow alive
    script_model("no", interpretation(intent: "confirmation", slots: { "confirmation" => "no" }))
    no_reply = described_class.new(hotel: hotel, message: "no", phone: "+60123456789").call
    expect(no_reply.payload[:reply_message]).to eq("No problem, let's carry on with your booking.")

    # 4. Ask again and confirm the end prompt, then reactivate with a greeting/booking request
    script_model("nevermind", interpretation(intent: "greeting", slots: {}))
    second_prompt = described_class.new(hotel: hotel, message: "nevermind", phone: "+60123456789").call
    expect(second_prompt.payload[:reply_message]).to eq("Your booking isn't finished yet. Would you like to end this chat? Please reply *Yes* to end, or *No* to carry on.")

    script_model("yes", interpretation(intent: "confirmation", slots: { "confirmation" => "yes" }))
    yes_reply = described_class.new(hotel: hotel, message: "yes", phone: "+60123456789").call
    expect(yes_reply.payload[:reply_message]).to include("Thank you for chatting with us")

    # No slots, just "can i book"
    script_model("hello, can i make booking", interpretation(slots: {}))
    reactivation_reply = described_class.new(hotel: hotel, message: "hello, can i make booking", phone: "+60123456789").call

    # It should ask for timing because the previous branch (with July) was archived
    expect(reactivation_reply.payload[:reply_message]).to include("date or month")
  end

  it "cancels the booking attempt and asks for the next step" do
    script_model("book early july for 2 adults", interpretation(slots: { "target_month" => 7, "target_year" => 2026, "month_segment" => "early", "days" => 3, "nights" => 2, "adults" => 2, "children" => 0 }))
    described_class.new(hotel: hotel, message: "book early july for 2 adults", phone: "+60123456789").call

    script_model("nevermind", interpretation(intent: "greeting", slots: {}))
    prompt = described_class.new(hotel: hotel, message: "nevermind", phone: "+60123456789").call
    expect(prompt.payload[:reply_message]).to eq("Your booking isn't finished yet. Would you like to end this chat? Please reply *Yes* to end, or *No* to carry on.")

    cancel_reply = described_class.new(hotel: hotel, message: "cancel attempt", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(cancel_reply.payload[:reply_message]).to eq("I've cancelled your booking attempt. Would you like to start a new booking, ask about hotel policies or information, or end the conversation?")
    expect(state.flow_status).to eq("active")
    expect(state.pending_question).to be_nil
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")

    script_model("i want to make booking", interpretation(slots: {}))
    fresh_reply = described_class.new(hotel: hotel, message: "i want to make booking", phone: "+60123456789").call

    expect(fresh_reply.payload[:reply_message]).to include("date or month")
    expect(fresh_reply.payload[:reply_message]).not_to include("couldn't find any rooms")
  end

  it "allows ending the conversation after cancelling a booking attempt" do
    script_model("book early july", interpretation(slots: { "target_month" => 7, "target_year" => 2026, "month_segment" => "early" }))
    described_class.new(hotel: hotel, message: "book early july", phone: "+60123456789").call

    script_model("cancel my attempt for booking", interpretation(intent: "reset", conversation_signals: { "is_reset" => true }))
    cancel_reply = described_class.new(hotel: hotel, message: "cancel my attempt for booking", phone: "+60123456789").call
    expect(cancel_reply.payload[:reply_message]).to include("end the conversation")

    script_model("end conversation", interpretation(intent: "greeting", conversation_signals: { "end_conversation" => true }))
    end_reply = described_class.new(hotel: hotel, message: "end conversation", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(end_reply.payload[:reply_message]).to eq("Thank you for chatting with us. Message us any time.")
    expect(state.flow_status).to eq("ended")
  end

  it "catches cancel attempt language before the reset branch" do
    script_model("book early july", interpretation(slots: { "target_month" => 7, "target_year" => 2026, "month_segment" => "early" }))
    described_class.new(hotel: hotel, message: "book early july", phone: "+60123456789").call

    script_model("cancel my attempt for booking", interpretation(intent: "reset", conversation_signals: { "is_reset" => true }))

    result = described_class.new(hotel: hotel, message: "cancel my attempt for booking", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(result.payload[:reply_message]).to eq("I've cancelled your booking attempt. Would you like to start a new booking, ask about hotel policies or information, or end the conversation?")
    expect(state.pending_question).to be_nil
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")
    expect(state.slots_payload.dig("booking_task", "branch", "target_month")).to be_nil
  end

  it "cancels a booking attempt from natural abandonment language and clears stale selection state" do
    prospect = create(:prospect, hotel: hotel, phone_number: "+60123456789")
    selected_option = {
      "selection_id" => "sel_1",
      "room_type_name" => "Deluxe Room",
      "check_in" => "2026-08-03",
      "check_out" => "2026-08-05",
      "selected_rate_plan" => { "rate_plan_id" => 2, "name" => "Standard Rate" }
    }
    branch = {
      "branch_id" => "branch-1",
      "target_month" => 8,
      "target_year" => 2026,
      "suggested_options" => [ { "room_type_name" => "Deluxe Room", "options" => [ selected_option ] } ],
      "suggestion_set_version" => 1,
      "selected_option" => selected_option,
      "confirmation_candidate" => selected_option,
      "selected_rate_plan_id" => 2,
      "selected_rate_plan_name" => "Standard Rate"
    }
    slots_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")
    create(:prospect_conversation_state, prospect: prospect, pending_question: "confirm_selection", active_flow: "booking_search", slots_payload: slots_payload)

    script_model("changed my mind", interpretation(intent: "greeting", slots: {}))

    result = described_class.new(hotel: hotel, message: "changed my mind", phone: "+60123456789").call
    state = prospect.reload.prospect_conversation_state

    expect(result.payload[:reply_message]).to eq("I've cancelled your booking attempt. Would you like to start a new booking, ask about hotel policies or information, or end the conversation?")
    expect(state.pending_question).to be_nil
    expect(state.active_flow).to be_nil
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")
    expect(state.slots_payload.dig("booking_task", "branch", "selected_option")).to be_nil
    expect(state.slots_payload.dig("booking_task", "branch", "confirmation_candidate")).to be_nil
    expect(state.slots_payload.dig("booking_task", "branch", "selected_rate_plan_id")).to be_nil
    expect(state.slots_payload.dig("booking_task", "branch", "selected_rate_plan_name")).to be_nil
  end

  it "cancels room-specific abandonment without ending the whole conversation" do
    script_model("book early july", interpretation(slots: { "target_month" => 7, "target_year" => 2026, "month_segment" => "early" }))
    described_class.new(hotel: hotel, message: "book early july", phone: "+60123456789").call

    script_model("forget the room", interpretation(intent: "greeting", slots: {}))

    result = described_class.new(hotel: hotel, message: "forget the room", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(result.payload[:reply_message]).to include("I've cancelled your booking attempt")
    expect(state.flow_status).to eq("active")
    expect(state.slots_payload.dig("booking_task", "status")).to eq("idle")
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
    slots_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "confirm_selection")
    create(:prospect_conversation_state, prospect: prospect, pending_question: "confirm_selection", slots_payload: slots_payload)

    script_messages(
      "what time is check in?" => interpretation(intent: "hotel_policy", topic: "hotel_policy", slots: {}),
      "yes" => interpretation(intent: "confirmation", slots: { "confirmation" => "yes" })
    )

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
    allow(AiConcierge::Tools::Booking::GenerateBookingUrlTool).to receive(:new).and_return(fake_generate_tool.new)

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

  # Frozen so "next month" is the June the scripted slots name, and 23 June
  # is still to come: an implicit year now rolls forward, and a wall-clock
  # June would make this thread a booking for a date already gone.
  it "resumes slot collection with a date after a hotel information interruption", frozen_time: Date.new(2026, 5, 15) do
    hotel.update!(amenities: [ "swimming_pool" ])

    script_messages(
      "i would like to make reservation on next month" => interpretation(slots: { "target_month" => 6, "target_year" => 2026 }),
      "may i know is there swimming pool" => interpretation(intent: "hotel_information", topic: "general_hotel_info", slots: {}),
      "ok, i want to book on 23 june" => interpretation(slots: { "check_in" => "2026-06-23" })
    )

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

  it "suspends active booking for guarded hotel knowledge and resumes afterward", frozen_time: Date.new(2026, 5, 15) do
    stub_knowledge_search(
      "general_info" => [],
      "faq,general_info,policy" => [
        knowledge_match("Parking is available near the lobby.", category: "faq")
      ]
    )

    script_messages(
      "i would like to make reservation on next month" => interpretation(slots: { "target_month" => 6, "target_year" => 2026 }),
      "is parking available there?" => interpretation(intent: "hotel_information", topic: "general_hotel_info", slots: {}),
      "ok, i want to book on 23 june" => interpretation(slots: { "check_in" => "2026-06-23" })
    )

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

  it "answers booking advice questions while a booking is suspended instead of resuming stale search" do
    hotel.property_policy.update!(cancellation_policy: "Full payment is required before confirmation.")

    script_messages(
      "i would like to make reservation on early june" =>
        interpretation(slots: { "target_month" => 6, "target_year" => 2026, "month_segment" => "early" }),
      "may i know is there swimming pool" => interpretation(intent: "hotel_information", topic: "general_hotel_info", slots: {}),
      "what should i aware during booking in this hotel?" => interpretation(intent: "hotel_policy", topic: "hotel_policy", slots: {})
    )

    first_reply = described_class.new(hotel: hotel, message: "i would like to make reservation on early june", phone: "+60123456789").call
    info_reply = described_class.new(hotel: hotel, message: "may i know is there swimming pool", phone: "+60123456789").call
    policy_reply = described_class.new(hotel: hotel, message: "what should i aware during booking in this hotel?", phone: "+60123456789").call
    state = hotel.prospects.lookup_by_phone("+60123456789").first.prospect_conversation_state.reload

    expect(first_reply.payload[:reply_message]).to include("How many days and nights")
    expect(info_reply.payload[:reply_message]).to be_present
    expect(policy_reply.payload[:reply_message]).to include("You can cancel under these terms")
    expect(policy_reply.payload[:reply_message]).not_to include("Sorry, I couldn't find any rooms")
    expect(state.slots_payload.dig("booking_task", "status")).to eq("suspended")
    expect(state.slots_payload.dig("information_task", "intent")).to eq("hotel_policy")
  end

  it "resumes a saved list and selects the row the guest numbered" do
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
    active_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "select_option")
    suspended_payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: active_payload).suspend_booking_for_information(intent: "hotel_policy", topic: "hotel_policy", pending_question: "select_option")
    create(:prospect_conversation_state, prospect: prospect, pending_question: nil, slots_payload: suspended_payload)

    # Nothing has told the model a list is waiting -- the thread is suspended --
    # so the row has to be read out of the message itself.
    script_model("no 2", interpretation(intent: "booking_search", slots: {}))

    result = described_class.new(hotel: hotel, message: "no 2", phone: "+60123456789").call
    state = prospect.reload.prospect_conversation_state

    expect(result.payload[:reply_message]).to include("Would you like to confirm")
    expect(state.slots_payload.dig("booking_task", "branch", "selected_option", "selection_id")).to eq("sel_2")
    expect(state.slots_payload.dig("booking_task", "pending_question")).to eq("confirm_selection")
  end

  it "keeps named room amenity questions on room information" do
    create(:room_type, hotel: hotel, name: "Deluxe Room", amenities: [ "wifi", "ac" ])
    script_model("what amenities does deluxe room have?", interpretation(intent: "room_information", topic: "room_information", slots: { "room_type_name" => "Deluxe Room" }, tool_hints: [ "get_room_type_details" ]))

    result = described_class.new(hotel: hotel, message: "what amenities does deluxe room have?", phone: "+60123456789").call

    expect(result.payload[:reply_message]).to include("Deluxe Room: Spacious room with city view")
    expect(result.payload[:reply_message]).to include("amenities include Free WiFi")
    expect(result.payload[:reply_message]).to include("amenities include Free WiFi, Air Conditioning")
  end

  # These specs were written against the interpreting pipeline, and their value
  # is that many of them script the model getting it *wrong* -- a transportation
  # question read as a booking, a month invented for a vague message. That is
  # worth keeping, so the interpretation is translated into the tool a model
  # holding it would have reached for, by the same ToolChoice the eval harness
  # uses for its agent_loop column.
  # Multi-turn tests script each message the model is asked about; anything they
  # do not name falls through to ReferenceClassifier.
  def script_messages(interpretations)
    stub_concierge_model(
      scripted: interpretations.to_h do |message, interpretation|
        [ message, AiConciergeEval::ScriptedChat::ToolChoice.new(interpretation: interpretation, message: message).call ]
      end
    )
  end

  def script_model(_message, interpretation)
    stub_concierge_model(interpretation: interpretation)
  end

  def interpretation(message_type: "booking_request", intent: "booking_search", topic: "booking_search", slots: {}, tool_hints: [ "search_booking_options" ], conversation_signals: {})
    {
      "message_type" => message_type,
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
