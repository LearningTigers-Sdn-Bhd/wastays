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

    it "redirects back to integrations page with success flash" do
      patch admin_integrations_path, params: { channex_api_key: "ch-123" }
      expect(response).to redirect_to(admin_integrations_path)
      follow_redirect!
      expect(response.body).to include("saved")
    end
  end
end
