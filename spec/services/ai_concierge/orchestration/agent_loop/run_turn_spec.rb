# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Orchestration::AgentLoop::RunTurn do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }

  def run(message: "hello")
    described_class.new(
      hotel: hotel, prospect: prospect, phone: nil,
      conversation_state: conversation_state, message: message
    )
  end

  describe "what the model is allowed to do" do
    # The single most important line in this file. The only route to a payable
    # quote is Booking::CompletionHandler, which is only reached when Postgres
    # says a confirmation was the open question -- so the model is never given
    # a tool that writes one.
    it "never offers the model a tool that generates a booking url" do
      expect(run.tools.map(&:name)).not_to include("generate_booking_url")
    end

    it "offers the tools by the short names it describes them by" do
      expect(run.tools.map(&:name)).to contain_exactly(
        "answer_hotel_question", "get_nearby_attractions",
        "get_room_type_details", "get_booking_context", "advance_booking"
      )
    end

    # RubyLLM derives a tool name from the full class name, which here would be
    # "ai_concierge--tools--llm--advance_booking". The model has to be able to
    # say the name back.
    it "does not leak ruby namespaces into the names the model sees" do
      expect(run.tools.map(&:name)).to all(match(/\A[a-z_]+\z/))
    end
  end

  describe "advancing a booking more than once in a turn" do
    # RubyLLM runs every tool call in a response before it notices the halt, so
    # a provider that ignores `calls: :one` could otherwise put the booking
    # through twice. This, not the halt, is what makes a duplicate quote
    # structurally impossible.
    it "refuses a second advance and does not run the booking again" do
      turn = run(message: "early august")
      tool = turn.tools.find { |candidate| candidate.name == "advance_booking" }

      first = tool.call({})
      second = tool.call({})

      expect(first).to be_a(RubyLLM::Tool::Halt)
      expect(second).to eq(AiConcierge::Tools::Llm::AdvanceBookingFunction::ALREADY_ADVANCED)
    end
  end

  describe "when the model fails" do
    def stub_chat(chat)
      allow_any_instance_of(AiConcierge::Providers::RubyLlmClient).to receive(:chat).and_return(chat)
    end

    # Blast radius is one turn, one guest, one sentence -- never a lost booking.
    it "still answers, and leaves the thread exactly as it found it" do
      stub_chat(instance_double(RubyLLM::Chat).tap do |chat|
        allow(chat).to receive(:with_instructions)
        allow(chat).to receive(:with_tools)
        allow(chat).to receive(:with_temperature)
        allow(chat).to receive(:before_tool_call)
        allow(chat).to receive(:after_tool_result)
        allow(chat).to receive(:ask).and_raise(RubyLLM::Error.new(nil, "provider down"))
      end)

      before_payload = conversation_state.slots_payload
      outcome = run.call

      expect(outcome.domain_result.dig(:extra_context, :message))
        .to eq(AiConcierge::MessageBuilders::DEFAULT_MESSAGE)
      expect(outcome.conversation_state.slots_payload).to eq(before_payload)
    end

    # A turn that failed after a tool already ran keeps that tool's work: it is
    # the guest's answer, and it is already written down.
    it "keeps what a tool already did when the model fails afterwards" do
      turn = run(message: "early august")
      tool = turn.tools.find { |candidate| candidate.name == "advance_booking" }
      tool.call({})

      allow(turn).to receive(:run).and_raise(Timeout::Error)

      expect(turn.call.domain_result[:active_flow]).to eq("booking_search")
    end
  end

  describe "a model that answers without reaching for a tool" do
    it "sends what it said to the guest" do
      chat = instance_double(RubyLLM::Chat)
      allow(chat).to receive(:with_instructions)
      allow(chat).to receive(:with_tools)
      allow(chat).to receive(:with_temperature)
      allow(chat).to receive(:before_tool_call)
      allow(chat).to receive(:after_tool_result)
      allow(chat).to receive(:ask).and_return(Struct.new(:content).new("Hello! How can I help?"))
      allow_any_instance_of(AiConcierge::Providers::RubyLlmClient).to receive(:chat).and_return(chat)

      expect(run.call.domain_result.dig(:extra_context, :message)).to eq("Hello! How can I help?")
    end
  end

  describe "hotel knowledge clarifications" do
    it "asks which facility, then resolves its opening hours without calling the model" do
      slots = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).update_information_task(
        intent: "hotel_information",
        topic: "general_hotel_info",
        question: "what hour do you open?",
        pending_question: "opening_hours_subject",
        context: { "choices" => [ "check-in", "facility" ] }
      )
      conversation_state.update!(slots_payload: slots)

      expect_any_instance_of(AiConcierge::Providers::RubyLlmClient).not_to receive(:chat)

      result = run(message: "facility").call.domain_result

      expect(result.dig(:extra_context, :result, "answer"))
        .to eq("Which facility do you mean, such as the pool, spa, fitness centre, or restaurant?")
      expect(result.dig(:slots_payload, "information_task", "pending_question")).to eq("facility_opening_hours")

      conversation_state.update!(slots_payload: result[:slots_payload])
      allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([
        {
          "content" => "The swimming pool opens at 7:00 AM.",
          "document_title" => "Swimming pool",
          "category" => "general_info",
          "distance" => 0.1
        }
      ])

      resolved = run(message: "pool").call.domain_result

      expect(resolved.dig(:extra_context, :result, "answer")).to eq("The swimming pool opens at 7:00 AM.")
      expect(resolved.dig(:slots_payload, "information_task", "pending_question")).to be_nil
    end

    it "resolves an ordinal policy choice without calling the model" do
      create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", check_out_time: "11:00 AM")
      allow_any_instance_of(HotelKnowledges::SearchService).to receive(:call).and_return([])
      slots = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).update_information_task(
        intent: "hotel_policy",
        topic: "hotel_policy",
        question: "what policy applies?",
        pending_question: "policy_topic",
        context: { "choices" => [ "check-in", "check-out", "cancellation", "house rules" ] }
      )
      conversation_state.update!(slots_payload: slots)

      expect_any_instance_of(AiConcierge::Providers::RubyLlmClient).not_to receive(:chat)

      result = run(message: "the second one").call.domain_result

      expect(result.dig(:extra_context, :result, "answer")).to eq("Check-out is by 11:00 AM.")
      expect(result.dig(:slots_payload, "information_task", "pending_question")).to be_nil
    end

    it "resolves an ordinal room choice without calling the model" do
      create(:room_type, hotel: hotel, name: "Ocean Villa King", description: "One king bed.")
      create(:room_type, hotel: hotel, name: "Ocean Villa Twin", description: "Two single beds.")
      slots = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).update_information_task(
        intent: "room_information",
        topic: "room_information",
        question: "tell me about ocean villa",
        pending_question: "room_type_choice",
        context: { "choices" => [ "Ocean Villa King", "Ocean Villa Twin" ] }
      )
      conversation_state.update!(slots_payload: slots)

      expect_any_instance_of(AiConcierge::Providers::RubyLlmClient).not_to receive(:chat)

      result = run(message: "the second one").call.domain_result

      expect(result.dig(:extra_context, :result, "room_type_name")).to eq("Ocean Villa Twin")
      expect(result.dig(:slots_payload, "information_task", "pending_question")).to be_nil
    end

    it "does not capture a new booking request as a knowledge clarification answer" do
      slots = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).update_information_task(
        intent: "hotel_information",
        topic: "general_hotel_info",
        question: "what hour do you open?",
        pending_question: "facility_opening_hours"
      )
      conversation_state.update!(slots_payload: slots)

      turn = run(message: "I want to book")

      expect(turn.send(:resolve_knowledge_clarification)).to be_nil
    end
  end
end
