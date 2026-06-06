# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Agents::KnowledgeAnswerAgent do
  let(:hotel) { create(:hotel, :with_ai_concierge) }
  let(:chat) { instance_double(RubyLLM::Chat) }
  let(:context) { instance_double(RubyLLM::Context, chat: chat) }
  let(:config) { double("ruby_llm_config") }

  before do
    allow(config).to receive(:openai_api_key=)
    allow(RubyLLM).to receive(:context).and_yield(config).and_return(context)
  end

  it "uses the hotel AI config and returns the synthesized answer" do
    allow(chat).to receive(:ask).and_return(double(content: "Breakfast is served from 7 AM to 10 AM."))

    result = described_class.new(
      hotel: hotel,
      message: "what time is breakfast?",
      intent: "hotel_information",
      topic: "hotel_faq",
      matches: [ { "content" => "Breakfast is served from 7 AM to 10 AM.", "document_title" => "Dining", "category" => "faq" } ]
    ).call

    expect(context).to have_received(:chat).with(model: hotel.ai_concierge_model_name, provider: hotel.ai_concierge_provider)
    expect(chat).to have_received(:ask).with(include("Answer only from HOTEL KNOWLEDGE SNIPPETS"))
    expect(result).to eq("Breakfast is served from 7 AM to 10 AM.")
  end

  it "raises a wrapped error when RubyLLM fails" do
    allow(chat).to receive(:ask).and_raise(RubyLLM::Error.new("bad request"))

    expect {
      described_class.new(
        hotel: hotel,
        message: "what time is breakfast?",
        intent: "hotel_information",
        topic: "hotel_faq",
        matches: []
      ).call
    }.to raise_error(described_class::KnowledgeAnswerError, /bad request/)
  end
end
