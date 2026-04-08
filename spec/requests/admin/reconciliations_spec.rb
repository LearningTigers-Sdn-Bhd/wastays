require 'rails_helper'

RSpec.describe "Admin::Reconciliations", type: :request do
  let(:superadmin) { create(:user, :superadmin) }
  let(:webhook_event) { create(:webhook_event, gateway: "stripe", external_id: "evt-show", status: "failed", payload: { id: "pay_show", metadata: {} }) }

  before do
    sign_in_as(superadmin)
  end

  describe "GET /index" do
    let!(:processed_event) do
      create(:webhook_event, gateway: "stripe", external_id: "evt-processed", status: "processed", payload: { id: "pay_1", metadata: {} }, created_at: Time.zone.parse("2026-04-01 12:00:00"))
    end

    let!(:failed_event) do
      create(:webhook_event, gateway: "billplz", external_id: "evt-failed", status: "failed", error_message: "Signature verification failed on callback payload.", payload: { id: "pay_2", metadata: {} }, created_at: Time.zone.parse("2026-04-01 13:00:00"))
    end

    let!(:pending_event) do
      create(:webhook_event, gateway: "curlec", external_id: "evt-pending", status: "pending", payload: { id: "pay_3", metadata: {} }, created_at: Time.zone.parse("2026-04-01 14:00:00"))
    end

    it "renders the payment issues dashboard with summary cards and queue content" do
      get admin_reconciliations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payment Issues")
      expect(response.body).to include("Monitor payment callbacks that need a manual review or booking retry.")
      expect(response.body).to include("Total Events")
      expect(response.body).to include("Needs Attention")
      expect(response.body).to include("Awaiting Review")
      expect(response.body).to include("Recovered")
      expect(response.body).to include("Event Queue")
      expect(response.body).to include("Showing 3 events")
      expect(response.body).to include("evt-failed")
      expect(response.body).to include("Signature verification failed on callback payload.")
      expect(response.body).to include("Retry Booking")
      expect(response.body).to include("All Gateways")
    end

    it "filters the queue by status" do
      get admin_reconciliations_path, params: { status: "failed" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Showing 1 event")
      expect(response.body).to include("evt-failed")
      expect(response.body).not_to include("evt-processed")
      expect(response.body).not_to include("evt-pending")
    end
  end

  describe "GET /show" do
    it "renders the payment issue detail view" do
      get "/admin/reconciliations/#{webhook_event.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Back to Payment Issues")
      expect(response.body).to include("Issue Status")
    end
  end
end
