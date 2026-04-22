require "rails_helper"

RSpec.describe PlatformControl::AiAnalyzerService do
  let(:entry) { create(:observation_entry) }
  let(:service) { described_class.new(entry) }

  before do
    allow(AppConfig).to receive(:get).with("gemini_api_key").and_return("fake_key")
  end

  it "returns error when API key is missing" do
    allow(AppConfig).to receive(:get).with("gemini_api_key").and_return(nil)
    expect(service.analyze[:error]).to include("not configured")
  end

  it "handles API failure gracefully" do
    fake_uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=fake_key")
    fake_response = double(is_a?: false, code: "500", body: "Error")

    allow(Net::HTTP).to receive(:new).and_return(double(use_ssl: true, "use_ssl=": true, request: fake_response))

    result = service.analyze
    expect(result[:error]).to include("API Request failed")
  end
end
