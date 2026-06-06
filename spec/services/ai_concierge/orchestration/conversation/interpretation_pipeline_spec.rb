require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Conversation::InterpretationPipeline do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:prospect) { create(:prospect, hotel: hotel) }
  let(:conversation_state) { create(:prospect_conversation_state, prospect: prospect) }

  it "builds summary, calls the interpreter, and validates the interpretation" do
    allow_any_instance_of(AiConcierge::Agents::InterpreterAgent).to receive(:call).and_return(interpretation)

    result = described_class.new(hotel: hotel, message: "hello").interpret(conversation_state: conversation_state)

    expect(result["intent"]).to eq("greeting")
  end

  it "raises when interpretation schema is invalid" do
    allow_any_instance_of(AiConcierge::Agents::InterpreterAgent).to receive(:call).and_return({ "intent" => "greeting" })

    expect {
      described_class.new(hotel: hotel, message: "hello").interpret(conversation_state: conversation_state)
    }.to raise_error(ArgumentError, "invalid interpretation payload")
  end

  it "guards hotel knowledge questions, merges slots, and returns a transition decision" do
    raw = interpretation(intent: "booking_search", topic: "booking_search", slots: {})

    prepared = described_class.new(
      hotel: hotel,
      message: "do you have house rules?"
    ).prepare(conversation_state: conversation_state, interpretation: raw)

    expect(prepared.interpretation["intent"]).to eq("hotel_policy")
    expect(prepared.decision[:action]).to eq(:librarian)
    expect(prepared.active_branch).to be_a(Hash)
  end

  it "resets stale booking context for a fresh booking request without details" do
    branch = { "target_month" => 8, "target_year" => 2026 }
    payload = AiConcierge::State::ConversationTaskManager.new(slots_payload: {}).activate_booking(branch, pending_question: "booking_timing")
    conversation_state.update!(pending_question: "booking_timing", slots_payload: payload)

    prepared = described_class.new(
      hotel: hotel,
      message: "I want to make booking"
    ).prepare(conversation_state: conversation_state, interpretation: interpretation(intent: "booking_search", topic: "booking_search", slots: {}))

    expect(prepared.active_branch["target_month"]).to be_nil
    expect(prepared.decision[:action]).to eq(:booking)
  end

  def interpretation(intent: "greeting", topic: "general", slots: {})
    {
      "message_type" => "greeting_or_unknown",
      "intent" => intent,
      "topic" => topic,
      "confidence" => 1.0,
      "slots" => slots,
      "tool_hints" => [],
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
