require "rails_helper"

RSpec.describe AiConciergeV3::InquiryResponder do
  let(:hotel) { create(:hotel, :with_ai_concierge) }

  before do
    # Mock Interpreter
    allow_any_instance_of(AiConciergeV3::InterpreterAgent).to receive(:call).and_return({
      "intent" => "greeting",
      "topic" => "general",
      "confidence" => 1.0,
      "slots" => {},
      "tool_hints" => [],
      "conversation_signals" => {
        "is_reset" => false, "is_resume" => false, "is_correction" => false, "starts_new_booking_branch" => false
      }
    })

    # Mock Messenger
    allow_any_instance_of(AiConciergeV3::MessengerAgent).to receive(:call).and_return({
      "reply_message" => "Hello! How can I help you with your stay or booking today?"
    })
  end

  it "returns an error result when concierge is disabled" do
    hotel.update!(ai_provider_enabled: false)

    result = described_class.new(hotel: hotel, message: "hello").call

    expect(result).not_to be_success
    expect(result.error).to eq("AI Concierge is not enabled for this hotel.")
  end

  it "delegates to the orchestrator for ready hotels" do
    result = described_class.new(hotel: hotel, message: "hello").call

    expect(result).to be_success
    expect(result.payload[:reply_message]).to eq("Hello! How can I help you with your stay or booking today?")
  end
end
