require "rails_helper"

RSpec.describe AiConcierge::Agents::InterpreterAgent do
  let(:hotel) { create(:hotel, ai_provider_name: "openai", ai_provider_key: "test-key") }
  let(:message) { "mid august for 2 people" }
  let(:summary) { {} }
  let(:today) { Date.new(2026, 5, 4) }
  let(:agent) { described_class.new(hotel: hotel, message: message, conversation_summary: summary, today: today) }
  let(:mock_chat) { double("RubyLLM::Chat") }
  let(:asked_prompts) { [] }

  let(:mock_response) do
    double("RubyLLM::Response", content: {
      "message_type" => "booking_request",
      "intent" => "booking_search",
      "topic" => "booking_search",
      "confidence" => 0.95,
      "slots" => {
        "target_month" => 8,
        "target_year" => 2026,
        "month_segment" => "mid",
        "party_size_total" => 2
      },
      "tool_hints" => [ "search_booking_options" ],
      "conversation_signals" => {
        "is_reset" => false,
        "is_resume" => false,
        "is_correction" => false,
        "starts_new_booking_branch" => false,
        "end_conversation" => false
      }
    })
  end

  before do
    allow(RubyLLM).to receive(:context).and_yield(double("RubyLLM::Config").as_null_object).and_return(double("RubyLLM::Context", chat: mock_chat))
    allow(mock_chat).to receive(:with_schema).and_return(mock_chat)
    allow(mock_chat).to receive(:ask) do |prompt|
      asked_prompts << prompt
      mock_response
    end
  end

  it "extracts month timing and total people via LLM" do
    result = agent.call

    expect(result["intent"]).to eq("booking_search")
    expect(result.dig("slots", "target_month")).to eq(8)
    expect(result.dig("slots", "month_segment")).to eq("mid")
    expect(result.dig("slots", "party_size_total")).to eq(2)
  end

  it "returns the internal message type from the LLM result" do
    result = agent.call

    expect(result["message_type"]).to eq("booking_request")
  end

  it "prompts the model to classify message type before intent and slots" do
    agent.call

    prompt = asked_prompts.last
    expect(prompt).to include("1. Choose exactly one message_type.")
    expect(prompt).to include("MESSAGE TYPE DECISION TREE")
    expect(prompt).to include("booking_selection")
    expect(prompt).to include("yes\" with pending_question=guest_count")
  end
end
