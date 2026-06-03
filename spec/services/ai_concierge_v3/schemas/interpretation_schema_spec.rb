require "rails_helper"
RSpec.describe AiConciergeV3::Schemas::InterpretationSchema do
  let(:valid_payload) do
    {
      "message_type" => "booking_request",
      "intent" => "booking_search",
      "topic" => "booking_search",
      "confidence" => 1.0,
      "slots" => {},
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

  it "requires a supported message type" do
    expect(described_class.new.valid?(valid_payload)).to be(true)

    valid_payload.delete("message_type")
    expect(described_class.new.valid?(valid_payload)).to be(false)
  end

  it "rejects unsupported message types" do
    valid_payload["message_type"] = "guest_vibes"

    expect(described_class.new.valid?(valid_payload)).to be(false)
  end
end
