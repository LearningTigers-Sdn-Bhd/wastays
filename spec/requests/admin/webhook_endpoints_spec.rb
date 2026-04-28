# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::WebhookEndpoints", type: :request do
  let(:admin_account) { create(:account) }
  let(:superadmin) { create(:user, :superadmin, account: admin_account) }
  let!(:endpoint) { create(:webhook_endpoint, name: "Existing Webhook", url: "https://example.com/1") }

  before { sign_in_as(superadmin) }

  describe "GET /admin/webhook_endpoints" do
    it "renders the index with list of endpoints" do
      get admin_webhook_endpoints_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Existing Webhook")
    end
  end

  describe "POST /admin/webhook_endpoints" do
    let(:valid_params) { { webhook_endpoint: { name: "New Bot", url: "https://bot.io", enabled: true } } }

    it "creates a new endpoint" do
      expect {
        post admin_webhook_endpoints_path, params: valid_params
      }.to change(WebhookEndpoint, :count).by(1)

      expect(response).to redirect_to(admin_webhook_endpoints_path)
    end
  end

  describe "PATCH /admin/webhook_endpoints/:id/toggle" do
    it "toggles the enabled status" do
      expect(endpoint.enabled).to be(true)
      patch toggle_admin_webhook_endpoint_path(endpoint)
      expect(endpoint.reload.enabled).to be(false)
      expect(response).to redirect_to(admin_webhook_endpoints_path)
    end
  end

  describe "POST /admin/webhook_endpoints/:id/test_ping" do
    it "sends a test ping" do
      stub_request(:post, endpoint.url).to_return(status: 200)
      post test_ping_admin_webhook_endpoint_path(endpoint)
      expect(response).to redirect_to(admin_webhook_endpoints_path)
      follow_redirect!
      expect(response.body).to include("successfully")
    end
  end

  describe "DELETE /admin/webhook_endpoints/:id" do
    it "deletes the endpoint" do
      expect {
        delete admin_webhook_endpoint_path(endpoint)
      }.to change(WebhookEndpoint, :count).by(-1)
      expect(response).to redirect_to(admin_webhook_endpoints_path)
    end
  end
end
