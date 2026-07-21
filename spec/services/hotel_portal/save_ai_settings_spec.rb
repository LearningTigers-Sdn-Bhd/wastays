# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::SaveAiSettings, type: :service do
  let(:hotel) { create(:hotel) }

  describe ".call" do
    let(:valid_params) do
      {
        ai_provider_enabled: "true",
        ai_concierge_tone: "business",
        ai_provider_name: "openai",
        ai_provider_key: "sk-proj-test"
      }
    end

    it "updates AI configuration when valid" do
      result = described_class.call(hotel, valid_params)
      expect(result).to be true
      expect(hotel.reload.ai_provider_enabled).to be true
      expect(hotel.ai_concierge_tone).to eq("business")
      expect(hotel.ai_provider_name).to eq("openai")
      expect(hotel.ai_provider_key).to eq("sk-proj-test")
    end

    context "when AI is enabled but details are missing" do
      let(:invalid_params) do
        {
          ai_provider_enabled: "true",
          ai_concierge_tone: "professional",
          ai_provider_name: "",
          ai_provider_key: ""
        }
      end

      it "adds errors to the hotel object and returns false" do
        result = described_class.call(hotel, invalid_params)
        expect(result).to be false
        expect(hotel.errors[:ai_provider_name]).to include("can't be blank")
        expect(hotel.errors[:ai_provider_key]).to include("can't be blank")
      end
    end
  end
end
