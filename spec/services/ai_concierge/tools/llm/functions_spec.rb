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

  describe "a price question that reaches an information tool" do
    # The 11pm enquiry the whole product exists to convert. A room description
    # does not answer it, but price interest is not booking consent either.
    it "hands the turn to deterministic price shopping" do
      result = tool(AiConcierge::Tools::Llm::AnswerHotelQuestionFunction, "how much is a room here?")
        .execute

      expect(result).to be_a(RubyLLM::Tool::Halt)
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
      expect(tool(AiConcierge::Tools::Llm::AdvanceBookingFunction, "hi").name).to eq("advance_booking")
      expect(tool(AiConcierge::Tools::Llm::AnswerHotelQuestionFunction, "hi").name).to eq("answer_hotel_question")
    end
  end
end
