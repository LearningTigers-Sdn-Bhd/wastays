require "rails_helper"

RSpec.describe PlatformControl::AiAnalyzerService do
  let(:entry) { create(:observation_entry) }
  let(:service) { described_class.new(entry) }
  let(:chat) { double("RubyLLM::Chat") }
  let(:context) { double("RubyLLM::Context", chat: chat) }
  let(:config) { double("RubyLLM::Config").as_null_object }
  let(:response) { double("RubyLLM::Response", content: "AI Analysis") }

  before do
    allow(RubyLLM).to receive(:context).and_yield(config).and_return(context)
    allow(chat).to receive(:ask).and_return(response)

    allow(AppConfig).to receive(:get).and_return(nil)
    allow(AppConfig).to receive(:get).with("observation_deck_ai_provider").and_return("gemini")
    allow(AppConfig).to receive(:get).with("gemini_api_key").and_return(nil)
    allow(AppConfig).to receive(:get).with("openai_api_key").and_return(nil)
    allow(AppConfig).to receive(:get).with("deepseek_api_key").and_return(nil)
    allow(AppConfig).to receive(:get).with("anthropic_api_key").and_return(nil)
  end

  it "uses the configured Gemini provider" do
    allow(AppConfig).to receive(:get).with("gemini_api_key").and_return("fake-gemini-key")

    result = service.analyze

    expect(context).to have_received(:chat).with(model: "gemini-2.5-flash", provider: :gemini)
    expect(config).to have_received(:gemini_api_key=).with("fake-gemini-key")
    expect(result[:model]).to eq("gemini-2.5-flash")
    expect(result[:html]).to include("AI Analysis")
  end

  it "uses the configured OpenAI provider" do
    allow(AppConfig).to receive(:get).with("observation_deck_ai_provider").and_return("openai")
    allow(AppConfig).to receive(:get).with("openai_api_key").and_return("fake-openai-key")

    result = service.analyze

    expect(context).to have_received(:chat).with(model: "gpt-4o-mini", provider: :openai)
    expect(config).to have_received(:openai_api_key=).with("fake-openai-key")
    expect(result[:model]).to eq("gpt-4o-mini")
  end

  it "uses the configured DeepSeek provider" do
    allow(AppConfig).to receive(:get).with("observation_deck_ai_provider").and_return("deepseek")
    allow(AppConfig).to receive(:get).with("deepseek_api_key").and_return("fake-deepseek-key")

    result = service.analyze

    expect(context).to have_received(:chat).with(model: "deepseek-chat", provider: :deepseek)
    expect(config).to have_received(:deepseek_api_key=).with("fake-deepseek-key")
    expect(result[:model]).to eq("deepseek-chat")
  end

  it "uses the configured Claude provider" do
    allow(AppConfig).to receive(:get).with("observation_deck_ai_provider").and_return("claude")
    allow(AppConfig).to receive(:get).with("anthropic_api_key").and_return("fake-anthropic-key")

    result = service.analyze

    expect(context).to have_received(:chat).with(model: "claude-haiku-4-5", provider: :anthropic)
    expect(config).to have_received(:anthropic_api_key=).with("fake-anthropic-key")
    expect(result[:model]).to eq("claude-haiku-4-5")
  end

  it "falls back to the first configured provider when selected provider has no key" do
    allow(AppConfig).to receive(:get).with("observation_deck_ai_provider").and_return("deepseek")
    allow(AppConfig).to receive(:get).with("openai_api_key").and_return("fake-openai-key")

    result = service.analyze

    expect(context).to have_received(:chat).with(model: "gpt-4o-mini", provider: :openai)
    expect(result[:model]).to eq("gpt-4o-mini")
  end

  it "returns error when API key is missing" do
    expect(service.analyze[:error]).to include("No AI provider API key configured")
  end
end
