require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Core::InquiryResponder do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  before do
    # Mock Interpreter
    allow_any_instance_of(AiConcierge::Agents::InterpreterAgent).to receive(:call).and_return({
      "message_type" => "greeting_or_unknown",
      "intent" => "greeting",
      "topic" => "general",
      "confidence" => 1.0,
      "slots" => {},
      "tool_hints" => [],
      "conversation_signals" => {
        "is_reset" => false, "is_resume" => false, "is_correction" => false, "starts_new_booking_branch" => false, "end_conversation" => false
      }
    })

    # Mock Messenger
    allow_any_instance_of(AiConcierge::Agents::MessengerAgent).to receive(:call).and_return({
      "reply_message" => "Hello! How can I help you with your stay or booking today?"
    })
  end

  it "returns an error result when concierge is disabled" do
    hotel.update!(ai_provider_enabled: false)

    result = described_class.new(hotel: hotel, message: "hello", phone: "+60123456789").call

    expect(result).not_to be_success
    expect(result.error).to eq("AI Concierge is not enabled for this hotel.")
  end

  it "delegates to the orchestrator for ready hotels" do
    result = described_class.new(hotel: hotel, message: "hello", phone: "+60123456789").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to eq("Hello! How can I help you with your stay or booking today?")
    expect(result.payload[:prospect_public_id]).to be_present
  end

  it "requires phone or prospect public id" do
    result = described_class.new(hotel: hotel, message: "hello").call

    expect(result).not_to be_success
    expect(result.error).to eq("Phone or prospect_public_id is required for AI concierge conversations")
  end

  it "returns an internal server error when the turn orchestrator fails unexpectedly" do
    allow(AiConcierge::Orchestration::TurnOrchestrator).to receive(:new).and_raise(StandardError, "boom")

    result = described_class.new(hotel: hotel, message: "hello", phone: "+60123456789").call

    expect(result).not_to be_success
    expect(result.status).to eq(:internal_server_error)
    expect(result.error).to eq("AI Concierge is temporarily unavailable.")
  end
end
