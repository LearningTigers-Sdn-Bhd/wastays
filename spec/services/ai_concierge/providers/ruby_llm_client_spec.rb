# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Providers::RubyLlmClient do
  let(:context) { instance_double(RubyLLM::Context, chat: chat) }
  let(:chat) { instance_double(RubyLLM::Chat) }
  let(:config) { double("ruby_llm_config").as_null_object }

  before do
    allow(RubyLLM).to receive(:context).and_yield(config).and_return(context)
  end

  it "builds a chat from the hotel model and provider mapping" do
    hotel = build(:hotel, ai_provider_enabled: true, ai_provider_name: "claude", ai_provider_key: "test-key")

    result = described_class.new(hotel: hotel).chat

    expect(config).to have_received(:anthropic_api_key=).with("test-key")
    expect(context).to have_received(:chat).with(model: hotel.ai_concierge_model_name, provider: :anthropic)
    expect(result).to eq(chat)
  end
end
