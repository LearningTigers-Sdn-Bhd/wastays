require "rails_helper"

RSpec.describe PlatformControl::AiAnalyzerService do
  let(:entry) { create(:observation_entry) }
  let(:service) { described_class.new(entry) }

  describe "Gemini integration" do
    before do
      allow(AppConfig).to receive(:get).with("ai_provider").and_return("gemini")
      allow(AppConfig).to receive(:get).with("gemini_api_key").and_return("fake_gemini_key")
    end

    it "uses gemini-1.5-flash model" do
      fake_response = double(is_a?: true, body: {
        candidates: [ { content: { parts: [ { text: "Gemini Analysis" } ] } } ]
      }.to_json)

      allow(Net::HTTP).to receive(:new).and_return(double(use_ssl: true, "use_ssl=": true, request: fake_response))

      result = service.analyze
      expect(result[:model]).to eq("gemini-1.5-flash")
      expect(result[:html]).to include("Gemini Analysis")
    end
  end

  describe "OpenAI integration" do
    before do
      allow(AppConfig).to receive(:get).with("ai_provider").and_return("openai")
      allow(AppConfig).to receive(:get).with("openai_api_key").and_return("fake_openai_key")
    end

    it "uses gpt-4o-mini model" do
      fake_response = double(is_a?: true, body: {
        choices: [ { message: { content: "OpenAI Analysis" } } ]
      }.to_json)

      allow(Net::HTTP).to receive(:new).and_return(double(use_ssl: true, "use_ssl=": true, request: fake_response))

      result = service.analyze
      expect(result[:model]).to eq("gpt-4o-mini")
      expect(result[:html]).to include("OpenAI Analysis")
    end
  end

  it "returns error when API key is missing" do
    allow(AppConfig).to receive(:get).with("ai_provider").and_return("gemini")
    allow(AppConfig).to receive(:get).with("gemini_api_key").and_return(nil)
    expect(service.analyze[:error]).to include("Gemini API key not configured")
  end
end
