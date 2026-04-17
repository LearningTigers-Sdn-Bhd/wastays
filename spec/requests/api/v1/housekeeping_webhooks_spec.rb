require "rails_helper"

RSpec.describe "Api::V1::HousekeepingWebhooks", type: :request do
  let(:booking) { create(:booking) }

  describe "POST /create" do
    it "creates a pending housekeeping request and later marks it completed" do
      post "/api/v1/housekeeping_webhooks", params: {
        booking_token: booking.confirmation_token,
        date: "2026-04-14",
        requests: [ "Change towels", "Add two water bottles" ],
        status: "pending"
      }

      expect(response).to have_http_status(:success)
      expect(booking.reload.housekeeping_requests.count).to eq(1)
      request = booking.housekeeping_requests.first
      expect(request.status).to eq("pending")
      expect(request.request_details).to include("Change towels")

      post "/api/v1/housekeeping_webhooks", params: {
        booking_token: booking.confirmation_token,
        date: "2026-04-14",
        requests: [ "Change towels", "Add two water bottles" ],
        status: "completed"
      }

      expect(response).to have_http_status(:success)
      expect(request.reload.status).to eq("completed")
      expect(request.completed_at).to be_present
    end
  end
end
