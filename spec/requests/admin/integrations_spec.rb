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

    context "unauthenticated" do
      it "redirects to login" do
        get admin_integrations_path
        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "PATCH /admin/integrations" do
    before { sign_in_as(superadmin) }

    it "saves the webhook URL to AppConfig" do
      patch admin_integrations_path, params: { webhook_url: "https://n8n.example.com/webhook/abc" }
      expect(AppConfig.get("webhook_url")).to eq("https://n8n.example.com/webhook/abc")
    end

    it "redirects back to integrations page with success flash" do
      patch admin_integrations_path, params: { webhook_url: "https://n8n.example.com/webhook/abc" }
      expect(response).to redirect_to(admin_integrations_path)
      follow_redirect!
      expect(response.body).to include("saved")
    end
  end

  describe "POST /admin/integrations/test_ping" do
    before { sign_in_as(superadmin) }

    context "when webhook URL is configured" do
      before { AppConfig.set("webhook_url", "https://n8n.example.com/webhook/abc") }

      it "POSTs to the webhook and redirects with success flash" do
        stub_request(:post, "https://n8n.example.com/webhook/abc").to_return(status: 200)
        post test_ping_admin_integrations_path
        expect(response).to redirect_to(admin_integrations_path)
        follow_redirect!
        expect(response.body).to include("Test ping sent")
      end

      it "shows error flash when webhook returns non-2xx" do
        stub_request(:post, "https://n8n.example.com/webhook/abc").to_return(status: 500)
        post test_ping_admin_integrations_path
        expect(response).to redirect_to(admin_integrations_path)
        follow_redirect!
        expect(response.body).to include("Test ping failed")
      end
    end

    context "when webhook URL is not configured" do
      before { AppConfig.find_by(key: "webhook_url")&.destroy }

      it "redirects with error flash" do
        post test_ping_admin_integrations_path
        expect(response).to redirect_to(admin_integrations_path)
        follow_redirect!
        expect(response.body).to include("No webhook URL configured")
      end
    end
  end
end
