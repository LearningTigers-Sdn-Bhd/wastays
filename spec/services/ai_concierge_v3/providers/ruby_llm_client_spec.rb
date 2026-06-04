# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConciergeV3::Providers::RubyLlmClient do
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

  it "exposes structured output support from the hotel configuration" do
    openai_hotel = build(:hotel, ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "test-key")
    deepseek_hotel = build(:hotel, ai_provider_enabled: true, ai_provider_name: "deepseek", ai_provider_key: "test-key")

    expect(described_class.new(hotel: openai_hotel)).to be_structured_output_supported
    expect(described_class.new(hotel: deepseek_hotel)).not_to be_structured_output_supported
  end
end
