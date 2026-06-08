# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Integrations", type: :request do
  let(:token) { SecureRandom.hex(6) }
  let(:admin_account) { create(:account, name: "Admin Integrations #{token}") }
  let(:hotel) { create(:hotel, account: admin_account) }
  let(:superadmin) { create(:user, :superadmin, account: admin_account, email: "admin-integrations-#{token}@example.com") }
  let(:regular_user) { create(:user, account: admin_account, email: "regular-integrations-#{token}@example.com") }
  let!(:regular_user_access) { create(:user_hotel_access, user: regular_user, hotel: hotel, role: create(:role, account: admin_account)) }

  describe "GET /admin/integrations" do
    context "as superadmin" do
      before { sign_in_as(superadmin) }

      it "returns 200" do
        get admin_integrations_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "as regular user" do
      before { sign_in_as(regular_user) }

      it "redirects away" do
        get admin_integrations_path
        expect(response).not_to have_http_status(:ok)
      end
    end
  end

  describe "PATCH /admin/integrations" do
    before { sign_in_as(superadmin) }

    it "saves Channex settings to AppConfig" do
      patch admin_integrations_path, params: { channex_api_key: "ch-123", channex_environment: "production" }
      expect(AppConfig.get("channex_api_key")).to eq("ch-123")
      expect(AppConfig.get("channex_environment")).to eq("production")
    end

    it "saves R2 settings to AppConfig" do
      patch admin_integrations_path, params: {
        r2_access_key_id: "r2-access",
        r2_secret_access_key: "r2-secret",
        r2_bucket: "wastays-production",
        r2_endpoint: "https://account.r2.cloudflarestorage.com/wastays-production",
        r2_region: "auto",
        r2_public_url: "https://cdn.example.com"
      }

      expect(AppConfig.get("r2_access_key_id")).to eq("r2-access")
      expect(AppConfig.get("r2_secret_access_key")).to eq("r2-secret")
      expect(AppConfig.get("r2_bucket")).to eq("wastays-production")
      expect(AppConfig.get("r2_endpoint")).to eq("https://account.r2.cloudflarestorage.com")
      expect(AppConfig.get("r2_region")).to eq("auto")
      expect(AppConfig.get("r2_public_url")).to eq("https://cdn.example.com")
    end

    it "saves AI provider keys to AppConfig" do
      patch admin_integrations_path, params: {
        gemini_api_key: "gemini-key",
        openai_api_key: "openai-key",
        deepseek_api_key: "deepseek-key",
        anthropic_api_key: "anthropic-key"
      }

      expect(AppConfig.get("gemini_api_key")).to eq("gemini-key")
      expect(AppConfig.get("openai_api_key")).to eq("openai-key")
      expect(AppConfig.get("deepseek_api_key")).to eq("deepseek-key")
      expect(AppConfig.get("anthropic_api_key")).to eq("anthropic-key")
    end

    it "redirects back to integrations page with success flash" do
      patch admin_integrations_path, params: { channex_api_key: "ch-123" }
      expect(response).to redirect_to(admin_integrations_path)
      follow_redirect!
      expect(response.body).to include("saved")
    end
  end
end
