# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AI concierge tools the model can see" do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }
  let(:recorder) { AiConcierge::Orchestration::AgentLoop::ToolRecorder.new }

  def context_for(message)
    AiConcierge::Orchestration::AgentLoop::TurnContext.new(
      hotel: hotel, prospect: prospect, phone: nil,
      conversation_state: conversation_state, message: message
    )
  end

  def tool(klass, message)
    klass.new(context: context_for(message), recorder: recorder)
  end

  before do
    allow(HotelKnowledges::SearchService).to receive(:new).and_return(instance_double(HotelKnowledges::SearchService, call: []))
  end

  describe "compound hotel questions" do
    let(:message) { "What time is check-in, and what time is check-out?" }

    before do
      create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", check_out_time: "11:00 AM")
    end

    it "answers two questions in order with labels and one optional action" do
      compound = tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, message)

      result = compound.execute(
        questions: [
          { evidence: "What time is check-in", label: "Check-in", kind: "hotel_policy", category: "policy", fact: "check_in_time" },
          { evidence: "what time is check-out", label: "Check-out", kind: "hotel_policy", category: "policy", fact: "check_out_time" }
        ],
        guest_language: "en"
      )

      expect(result).to eq(answered: true, question_count: 2)
      answer = recorder.outcome.domain_result.dig(:extra_context, :message)
      expect(answer).to include("1. Check-in — You can check in from 3:00 PM.")
      expect(answer).to include("2. Check-out — Check-out is by 11:00 AM.")
      expect(answer.scan("compare rooms").size).to eq(1)
      expect(answer).to include("Is there anything else you’d like to know?")
    end

    it "rejects evidence that is not present in the guest message" do
      compound = tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, message)

      compound.execute(questions: [
        { evidence: "invented check-in question", label: "Check-in", kind: "hotel_policy" },
        { evidence: "what time is check-out", label: "Check-out", kind: "hotel_policy" }
      ])

      expect(recorder.outcome.domain_result.dig(:extra_context, :message))
        .to eq("Please send your request again in one message.")
    end

    it "keeps booking slots from a mixed information and booking message" do
      mixed = "What time is check-in, and is parking available? I need a room in August 2026 for 2 adults."
      compound = tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, mixed)

      compound.execute(
        questions: [
          { evidence: "What time is check-in", label: "Check-in", kind: "hotel_policy", category: "policy", fact: "check_in_time" },
          { evidence: "is parking available", label: "Parking", kind: "hotel_information", category: "general_info", search_terms: "parking" }
        ],
        commercial: {
          intent: "booking",
          slots: { target_month: 8, target_year: 2026, adults: 2 },
          evidence: { timing: "August 2026", party: "2 adults" }
        }
      )

      booking = recorder.outcome.domain_result.slots_payload.fetch("booking_task")
      expect(booking.dig("branch", "target_month")).to eq(8)
      expect(booking.dig("branch", "target_year")).to eq(2026)
      expect(booking.dig("branch", "adults")).to eq(2)
      expect(recorder.outcome.domain_result.dig(:extra_context, :message)).to start_with("Here is what I found:")
      expect(recorder.outcome.domain_result.dig(:extra_context, :knowledge_outcome)).to eq("partial")
      expect(recorder.outcome.domain_result.slots_payload.dig("information_task", "consecutive_failure_count")).to eq(1)
      expect(recorder.outcome.domain_result.dig(:extra_context, :message)).to include("Parking — The hotel has not listed")
    end

    it "answers one hotel question before continuing the booking from the same message" do
      mixed = "Does the hotel have parking, and what rooms are available from 10 October to 12 October for two adults?"
      match = {
        "content" => "Parking is available for hotel guests.",
        "category" => "general_info",
        "distance" => 0.1
      }
      allow(HotelKnowledges::SearchService).to receive(:new)
        .and_return(instance_double(HotelKnowledges::SearchService, call: [ match ]))

      tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, mixed).execute(
        questions: [
          {
            evidence: "Does the hotel have parking",
            label: "parking",
            kind: "hotel_information",
            category: "general_info",
            search_terms: "parking"
          }
        ],
        commercial: {
          intent: "booking",
          slots: { check_in: "2026-10-10", check_out: "2026-10-12", adults: 2 },
          evidence: { timing: "10 October", checkout: "12 October", party: "two adults" }
        }
      )

      result = recorder.outcome.domain_result
      expect(result.dig(:extra_context, :message)).to start_with("Parking is available for hotel guests.")
      expect(result.slots_payload.dig("booking_task", "branch", "check_in")).to eq("2026-10-10")
      expect(result.slots_payload.dig("booking_task", "branch", "check_out")).to eq("2026-10-12")
      expect(result.slots_payload.dig("booking_task", "branch", "adults")).to eq(2)
    end

    it "answers every question without a count cap and capitalizes labels" do
      expanded = "What time is check-in, what time is check-out, what is the cancellation policy, and are pets allowed?"
      compound = tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, expanded)

      compound.execute(
        questions: [
          { evidence: "What time is check-in", label: "check-in", kind: "hotel_policy", fact: "check_in_time" },
          { evidence: "what time is check-out", label: "check-out", kind: "hotel_policy", fact: "check_out_time" },
          { evidence: "what is the cancellation policy", label: "cancellation", kind: "hotel_policy", fact: "cancellation_policy" },
          { evidence: "are pets allowed", label: "pet policy", kind: "hotel_policy", search_terms: "pets" }
        ]
      )

      answer = recorder.outcome.domain_result.dig(:extra_context, :message)
      expect(answer).to include("1. Check-in")
      expect(answer).to include("4. Pet policy")
      expect(answer).not_to include("first three questions")
    end

    context "when booking confirmation is pending" do
      let(:conversation_state) do
        selected = {
          "selection_id" => "selection-1",
          "room_type_name" => "Garden Suite",
          "check_in" => "2026-08-01",
          "check_out" => "2026-08-03",
          "currency" => "MYR",
          "total_price" => 400
        }
        create(
          :prospect_conversation_state,
          :awaiting_confirmation,
          prospect: prospect,
          selected_option: selected
        )
      end

      it "answers the questions and asks for confirmation again without creating a quote" do
        compound = tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, message)

        expect {
          compound.execute(questions: [
            { evidence: "What time is check-in", label: "Check-in", kind: "hotel_policy", fact: "check_in_time" },
            { evidence: "what time is check-out", label: "Check-out", kind: "hotel_policy", fact: "check_out_time" }
          ])
        }.not_to change(BookingQuote, :count)

        result = recorder.outcome.domain_result
        expect(result.pending_question).to eq("confirm_selection")
        expect(result.dig(:extra_context, :message)).to start_with("Here is what I found:")
        expect(result.dig(:extra_context, :message)).to include("Would you like to confirm your quotation")
        expect(result.slots_payload.dig("information_task", "pending_question")).to be_nil
      end
    end
  end

  describe "knowledge outcomes and escalation" do
    let(:message) { "Does the hotel have a helipad?" }
    let(:question) do
      {
        evidence: message,
        label: "Helipad",
        kind: "hotel_information",
        category: "faq",
        search_terms: "helipad",
        scope: "specific"
      }
    end

    it "marks a single unavailable question unavailable and increments once" do
      result = tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, message).execute(questions: [ question ])
      domain_result = recorder.outcome.domain_result

      expect(result).to eq(answered: false, question_count: 1)
      expect(domain_result.extra_context).to include(
        knowledge_outcome: "unavailable",
        failure_count: 1,
        failure_topics: [ "an FAQ answer" ],
        human_requested: false
      )
      expect(domain_result.slots_payload.dig("information_task", "consecutive_failure_count")).to eq(1)
    end

    it "requests staff exactly when no-answer reaches the configured threshold" do
      create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [ "no_answer" ], escalation_attempts: 2)

      tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, message).execute(questions: [ question ])
      first = recorder.outcome.domain_result
      conversation_state.update!(slots_payload: first.slots_payload)

      expect(first.needs_human_support).to be(false)
      expect(first.next_action.kind).to eq("none")

      tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, message).execute(questions: [ question ])
      second = recorder.outcome.domain_result

      expect(second.needs_human_support).to be(true)
      expect(second.extra_context).to include(
        knowledge_outcome: "unavailable",
        failure_count: 2,
        escalation_trigger: "no_answer",
        human_requested: true
      )
      expect(second.extra_context[:message]).to include("asked a team member")
      expect(second.extra_context[:message]).not_to include("compare rooms")
    end

    it "never auto-hands off repeated no-answer when the trigger is disabled" do
      create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [], escalation_attempts: 1)

      2.times do
        tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, message).execute(questions: [ question ])
        conversation_state.update!(slots_payload: recorder.outcome.domain_result.slots_payload)
      end

      expect(recorder.outcome.domain_result.needs_human_support).to be(false)
      expect(recorder.outcome.domain_result.extra_context[:failure_count]).to eq(2)
      expect(recorder.outcome.domain_result.extra_context[:escalation_trigger]).to be_nil
    end

    it "hands off an enabled complaint without appending a booking or sales offer" do
      create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [ "complaint" ])
      complaint = "The room is filthy and I want to complain"

      tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, complaint).execute(
        support_requests: [ { evidence: complaint, trigger: "complaint" } ],
        commercial: { intent: "booking", slots: { target_month: 10 } }
      )
      result = recorder.outcome.domain_result

      expect(result.needs_human_support).to be(true)
      expect(result.extra_context[:escalation_trigger]).to eq("complaint")
      expect(result.extra_context[:message]).to include("asked a team member")
      expect(result.extra_context[:message]).not_to include("room", "booking", "compare")
      expect(result.slots_payload).not_to have_key("booking_task")
    end

    it "treats a general payment-policy signal as hotel knowledge rather than a payment escalation" do
      create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [ "payment_question" ])
      policy_question = "What is your payment policy?"

      tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, policy_question).execute(
        support_requests: [ { evidence: policy_question, trigger: "payment_question" } ]
      )
      result = recorder.outcome.domain_result

      expect(result.needs_human_support).to be(false)
      expect(result.extra_context[:knowledge_outcome]).to eq("clarification")
      expect(result.extra_context[:failure_count]).to eq(0)
      expect(result.extra_context[:escalation_trigger]).to be_nil
    end

    it "hands off an enabled guest-specific charge issue" do
      create(:hotel_guest_contact, hotel: hotel, escalation_triggers: [ "payment_question" ])
      charge_issue = "I was charged twice for my booking"

      tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, charge_issue).execute(
        support_requests: [ { evidence: charge_issue, trigger: "payment_question" } ]
      )

      expect(recorder.outcome.domain_result.needs_human_support).to be(true)
      expect(recorder.outcome.domain_result.extra_context[:escalation_trigger]).to eq("payment_question")
    end
  end

  describe "a price question that reaches an information tool" do
    # The 11pm enquiry the whole product exists to convert. A room description
    # does not answer it, but price interest is not booking consent either.
    it "hands the turn to deterministic price shopping" do
      result = tool(AiConcierge::Tools::Llm::AnswerHotelQuestionFunction, "how much is a room here?")
        .execute

      expect(result).to eq(advanced: true)
      expect(recorder.outcome.domain_result[:active_flow]).to eq("booking_search")
      expect(recorder.outcome.domain_result[:pending_question]).to eq("booking_timing")
      expect(recorder.outcome.domain_result.dig(:slots_payload, "booking_task", "purpose")).to eq("price_exploration")
      expect(recorder.outcome.domain_result[:action_name]).to be_nil
    end


    it "keeps an explicit request to book the cheapest room in booking commitment" do
      tool(AiConcierge::Tools::Llm::AdvanceBookingFunction, "book the cheapest room")
        .execute

      result = recorder.outcome.domain_result
      expect(result.dig(:slots_payload, "booking_task", "purpose")).to eq("booking")
      expect(result[:action_name]).to eq("request_quote")
    end

    it "moves an empty price search into booking after an explicit booking request" do
      payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).set_booking_purpose("price_exploration")
      conversation_state.update!(slots_payload: payload)

      tool(AiConcierge::Tools::Llm::AdvanceBookingFunction, "I want to book a room").execute

      result = recorder.outcome.domain_result
      expect(result.dig(:slots_payload, "booking_task", "purpose")).to eq("booking")
      expect(result[:pending_question]).to eq("booking_timing")
      expect(result[:action_name]).to eq("request_quote")
    end

    it "does the same when the guest asks the price of a named room" do
      tool(AiConcierge::Tools::Llm::GetRoomTypeDetailsFunction, "what is the price of the ocean villa per night?")
        .execute

      expect(recorder.outcome.domain_result[:pending_question]).to eq("booking_timing")
    end

    # "Room service" contains the word room and is never a room.
    it "leaves room service alone" do
      tool(AiConcierge::Tools::Llm::AnswerHotelQuestionFunction, "how much is room service?")
        .execute

      expect(recorder.outcome.domain_result[:pending_question]).to be_nil
    end
  end

  describe "what the booking tool contributes" do
    let(:conversation_state) { create(:prospect_conversation_state, :awaiting_confirmation, prospect: prospect) }

    # "Yes" means a confirmation only while a confirmation is what was asked.
    # At any other moment it is just a word, and the lock that decides which
    # moment it is lives in Postgres.
    it "reads a yes as confirmation only while a confirmation is pending" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
        slots: { "confirmation" => "yes" }, signals: {}, pending_question: "confirm_selection"
      ).call

      expect(interpretation["intent"]).to eq("confirmation")
    end

    # The model is asked for a confirmation and does not always send one. A
    # bare "yes" then arrived as a booking turn with nothing in it, and the
    # ladder answered it with the catalogue the guest had already chosen from.
    it "reads the guest's own yes when the model sends no confirmation" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
        slots: {}, signals: {}, pending_question: "confirm_selection", message: "yes"
      ).call

      expect(interpretation["intent"]).to eq("confirmation")
      expect(interpretation.dig("slots", "confirmation")).to eq("yes")
    end

    it "reads the guest's own no the same way" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
        slots: {}, signals: {}, pending_question: "confirm_selection", message: "no thanks"
      ).call

      expect(interpretation.dig("slots", "confirmation")).to eq("no")
    end

    it "reads a yes written in the guest's own language" do
      %w[baik 好的 可以].each do |word|
        interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
          slots: {}, signals: {}, pending_question: "confirm_selection", message: word
        ).call

        expect(interpretation.dig("slots", "confirmation")).to eq("yes")
      end
    end

    # The word only means a confirmation where a confirmation was asked for,
    # and a message that is not one is never read as a yes.
    it "reads nothing from a message that answers something else" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
        slots: {}, signals: {}, pending_question: "confirm_selection", message: "what time is check in"
      ).call

      expect(interpretation.dig("slots", "confirmation")).to be_nil
      expect(interpretation["intent"]).to eq("booking_search")
    end

    # The party split asks a yes/no too -- its own reply tells the guest to
    # answer *Yes* -- and a yes the model did not pass along left the hotel
    # asking the same question again.
    it "reads the guest's own yes when the party split is the open question" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
        slots: {}, signals: {}, pending_question: "party_split", message: "yes"
      ).call

      expect(interpretation.dig("slots", "confirmation")).to eq("yes")
    end

    it "does not read a yes when no confirmation is pending" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
        slots: {}, signals: {}, pending_question: "select_option", message: "yes"
      ).call

      expect(interpretation.dig("slots", "confirmation")).to be_nil
    end

    it "reads a row number at confirmation as a new option selection" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
        slots: {}, signals: {}, pending_question: "confirm_selection", message: "2"
      ).call

      expect(interpretation["intent"]).to eq("option_selection")
    end

    it "reads the same yes as nothing in particular when no confirmation is pending" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
        slots: { "confirmation" => "yes" }, signals: {}, pending_question: "guest_count"
      ).call

      expect(interpretation["intent"]).to eq("booking_search")
    end

    it "never takes an action or a next question from the model" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
        slots: { "adults" => 2 }, signals: {}, pending_question: nil
      ).call

      expect(interpretation["slots"]).to eq("adults" => 2)
      expect(interpretation).not_to have_key("action")
      expect(interpretation).not_to have_key("pending_question")
    end

    it "reads a positive price-option answer as confirmation" do
      %w[yes baik 好的].each do |answer|
        interpretation = AiConcierge::Tools::Llm::AdvanceBookingFunction::SyntheticInterpretation.new(
          slots: {}, signals: {}, pending_question: "price_option_continuation", message: answer
        ).call

        expect(interpretation.dig("slots", "confirmation")).to eq("yes")
      end
    end
  end

  describe "the names the model sees" do
    it "uses short names rather than ruby namespaces" do
      expect(tool(AiConcierge::Tools::Llm::HandleGuestTurnFunction, "hi").name).to eq("handle_guest_turn")
    end
  end
end
