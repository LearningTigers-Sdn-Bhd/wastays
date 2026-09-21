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

      it "renders one tab per integration" do
        get admin_integrations_path

        Admin::IntegrationsController::TABS.each do |tab|
          expect(response.body).to include(tab[:label])
        end
      end

      it "gives every panel a visible heading" do
        get admin_integrations_path

        [ "Channel manager", "Storage", "AI providers", "AroundThat" ].each do |title|
          expect(response.body).to include(%(<h2 class="text-base font-semibold tracking-tight text-foreground">#{title}</h2>))
        end
      end

      it "opens the first tab by default" do
        get admin_integrations_path

        expect(response.body).to include('data-panels-ui--tabs-active-value="channel_manager"')
      end

      it "opens the tab named in the query string" do
        get admin_integrations_path(tab: "around_that")

        expect(response.body).to include('data-panels-ui--tabs-active-value="around_that"')
      end

      it "ignores an unknown tab" do
        get admin_integrations_path(tab: "nope")

        expect(response.body).to include('data-panels-ui--tabs-active-value="channel_manager"')
      end

      it "shows a stored key in a maskable field" do
        AppConfig.set("aroundthat_api_key", "at-stored-key")

        get admin_integrations_path

        expect(response.body).to include('type="password"')
        expect(response.body).to include("at-stored-key")
      end

      it "wires the reveal toggle to the password-toggle controller" do
        get admin_integrations_path

        expect(response.body).to include('data-controller="password-toggle"')
        expect(response.body).to include("password-toggle#toggle")
      end

      it "wires both connection tests to the connection-test controller" do
        get admin_integrations_path

        expect(response.body).to include("connection-test#run")
        expect(response.body).to include(test_r2_connection_admin_integrations_path)
        expect(response.body).to include(test_around_that_connection_admin_integrations_path)
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

  describe "POST /admin/integrations/test_around_that_connection" do
    let(:base_url) { "https://api.aroundthat.test/v1" }

    before do
      AppConfig.set("aroundthat_api_key", "at-key")
      AppConfig.set("aroundthat_base_url", base_url)
      AppConfig.set("aroundthat_environment", "staging")
    end

    it "keeps a regular user out" do
      sign_in_as(regular_user)

      post test_around_that_connection_admin_integrations_path

      expect(response).not_to have_http_status(:ok)
    end

    it "returns the success message when AroundThat answers" do
      sign_in_as(superadmin)
      stub_request(:get, base_url).to_return(status: 200, body: "{}")

      post test_around_that_connection_admin_integrations_path

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(response.parsed_body["message"]).to include("api.aroundthat.test")
    end

    it "returns the failure message when AroundThat rejects the key" do
      sign_in_as(superadmin)
      stub_request(:get, base_url).to_return(status: 401)

      post test_around_that_connection_admin_integrations_path

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["success"]).to be(false)
      expect(response.parsed_body["message"]).to include("rejected the API key")
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

    it "saves AroundThat settings to AppConfig" do
      patch admin_integrations_path, params: {
        aroundthat_api_key: "at-key",
        aroundthat_base_url: "https://api.aroundthat.example/v1",
        aroundthat_environment: "production"
      }

      expect(AppConfig.get("aroundthat_api_key")).to eq("at-key")
      expect(AppConfig.get("aroundthat_base_url")).to eq("https://api.aroundthat.example/v1")
      expect(AppConfig.get("aroundthat_environment")).to eq("production")
    end

    it "clears an AroundThat value when the field is submitted empty" do
      AppConfig.set("aroundthat_api_key", "at-key")

      patch admin_integrations_path, params: { aroundthat_api_key: "" }

      expect(AppConfig.get("aroundthat_api_key")).to eq("")
    end

    it "redirects back to integrations page with success flash" do
      patch admin_integrations_path, params: { channex_api_key: "ch-123" }
      expect(response).to redirect_to(admin_integrations_path(tab: "channel_manager"))
      follow_redirect!
      expect(response.body).to include("saved")
    end

    it "returns to the tab the form was posted from" do
      patch admin_integrations_path, params: { tab: "around_that", aroundthat_api_key: "at-key" }

      expect(response).to redirect_to(admin_integrations_path(tab: "around_that"))
    end

    it "falls back to the first tab when the posted tab is unknown" do
      patch admin_integrations_path, params: { tab: "nope", channex_api_key: "ch-123" }

      expect(response).to redirect_to(admin_integrations_path(tab: "channel_manager"))
    end
  end
end
