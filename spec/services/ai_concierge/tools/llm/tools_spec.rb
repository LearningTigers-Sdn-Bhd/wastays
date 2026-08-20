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
    # The 11pm enquiry the whole product exists to convert. Answering it with a
    # room description instead of taking the guest into a booking is the
    # expensive kind of wrong, so it is not left to the model's judgement.
    it "hands the turn to the booking machine instead of answering it" do
      result = tool(AiConcierge::Tools::Llm::AnswerHotelQuestionTool, "how much is a room here?")
        .execute(question: "how much is a room here?")

      expect(result).to be_a(RubyLLM::Tool::Halt)
      expect(recorder.outcome.intent).to eq("booking_search")
      expect(recorder.outcome.domain_result[:pending_question]).to eq("booking_timing")
    end

    it "does the same when the guest asks the price of a named room" do
      tool(AiConcierge::Tools::Llm::GetRoomTypeDetailsTool, "what is the price of the ocean villa per night?")
        .execute(query: "what is the price of the ocean villa per night?")

      expect(recorder.outcome.intent).to eq("booking_search")
    end

    # "Room service" contains the word room and is never a room.
    it "leaves room service alone" do
      tool(AiConcierge::Tools::Llm::AnswerHotelQuestionTool, "how much is room service?")
        .execute(question: "how much is room service?")

      expect(recorder.outcome.intent).to eq("hotel_information")
    end
  end

  describe "what the booking tool contributes" do
    let(:conversation_state) { create(:prospect_conversation_state, :awaiting_confirmation, prospect: prospect) }

    # "Yes" means a confirmation only while a confirmation is what was asked.
    # At any other moment it is just a word, and the lock that decides which
    # moment it is lives in Postgres.
    it "reads a yes as confirmation only while a confirmation is pending" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingTool::SyntheticInterpretation.new(
        slots: { "confirmation" => "yes" }, signals: {}, pending_question: "confirm_selection"
      ).call

      expect(interpretation["intent"]).to eq("confirmation")
    end

    it "reads the same yes as nothing in particular when no confirmation is pending" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingTool::SyntheticInterpretation.new(
        slots: { "confirmation" => "yes" }, signals: {}, pending_question: "guest_count"
      ).call

      expect(interpretation["intent"]).to eq("booking_search")
    end

    it "never takes an action or a next question from the model" do
      interpretation = AiConcierge::Tools::Llm::AdvanceBookingTool::SyntheticInterpretation.new(
        slots: { "adults" => 2 }, signals: {}, pending_question: nil
      ).call

      expect(interpretation["slots"]).to eq("adults" => 2)
      expect(interpretation).not_to have_key("action")
      expect(interpretation).not_to have_key("pending_question")
    end
  end

  describe "the names the model sees" do
    it "uses short names rather than ruby namespaces" do
      expect(tool(AiConcierge::Tools::Llm::AdvanceBookingTool, "hi").name).to eq("advance_booking")
      expect(tool(AiConcierge::Tools::Llm::AnswerHotelQuestionTool, "hi").name).to eq("answer_hotel_question")
    end
  end
end
