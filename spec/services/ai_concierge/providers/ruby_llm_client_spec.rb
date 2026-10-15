# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Providers::RubyLlmClient do
  let(:context) { instance_double(RubyLLM::Context, chat: chat) }
  let(:chat) { instance_double(RubyLLM::Chat, with_thinking: nil, with_instructions: nil) }
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

  # 2.5 Flash thinks unless told not to, and those tokens bill as output on
  # the priciest line gemini sells -- twice a turn, unmeasured.
  it "tells gemini not to think" do
    hotel = build(:hotel, ai_provider_enabled: true, ai_provider_name: "gemini", ai_provider_key: "test-key")

    result = described_class.new(hotel: hotel).chat

    expect(chat).to have_received(:with_thinking).with(budget: 0)
    expect(result).to eq(chat)
  end

  # The same config becomes `reasoning_effort` on openai, which the model in
  # that seat does not take.
  it "leaves the other providers' requests alone" do
    %w[openai claude].each do |provider|
      hotel = build(:hotel, ai_provider_enabled: true, ai_provider_name: provider, ai_provider_key: "test-key")

      described_class.new(hotel: hotel).chat

      expect(chat).not_to have_received(:with_thinking)
    end
  end

  describe "#add_cacheable_instructions" do
    # claude is the only one that has to be asked. The other two cache a stable
    # prefix on their own, so there is nothing to write -- only something to
    # stop breaking, which is why the instructions are split at all.
    it "marks the block for claude to keep" do
      hotel = build(:hotel, ai_provider_enabled: true, ai_provider_name: "claude", ai_provider_key: "test-key")

      described_class.new(hotel: hotel).add_cacheable_instructions(chat, "the stable half")

      expect(chat).to have_received(:with_instructions).with("the stable half", cache_until_here: true)
    end

    it "hands the other providers the text unchanged" do
      %w[openai gemini].each do |provider|
        hotel = build(:hotel, ai_provider_enabled: true, ai_provider_name: provider, ai_provider_key: "test-key")
        expect(chat).to receive(:with_instructions).with("the stable half")

        described_class.new(hotel: hotel).add_cacheable_instructions(chat, "the stable half")
      end
    end
  end
end
