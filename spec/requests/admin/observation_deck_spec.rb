# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::ObservationDeck", type: :request do
  let(:account) { create(:account, name: "Observation Deck Admin") }
  let(:superadmin) { create(:user, :superadmin, account: account, email: "observation-admin@example.com") }

  before { sign_in_as(superadmin) }

  describe "GET /admin/observation_deck" do
    it "links to integrations when no AI providers are configured" do
      get admin_observation_deck_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Configure AI Providers")
      expect(response.body).to include(admin_integrations_path)
    end

    it "shows only configured AI providers in the selector" do
      AppConfig.set("openai_api_key", "openai-key")

      get admin_observation_deck_index_path

      expect(response.body).to include("OpenAI")
      expect(response.body).not_to include(">DeepSeek<")
      expect(response.body).not_to include(">Claude<")
    end
  end

  describe "POST /admin/observation_deck/update_config" do
    it "saves a configured provider as the Observation Deck provider" do
      AppConfig.set("openai_api_key", "openai-key")

      post update_config_admin_observation_deck_index_path, params: { observation_deck_ai_provider: "openai" }

      expect(AppConfig.get("observation_deck_ai_provider")).to eq("openai")
      expect(AppConfig.get("ai_provider")).to be_nil
    end

    it "does not save an unconfigured provider" do
      AppConfig.set("openai_api_key", "openai-key")

      post update_config_admin_observation_deck_index_path, params: { observation_deck_ai_provider: "deepseek" }

      expect(AppConfig.get("observation_deck_ai_provider")).to be_nil
    end
  end
end
