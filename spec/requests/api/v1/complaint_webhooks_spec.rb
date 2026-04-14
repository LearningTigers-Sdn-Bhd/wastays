require "rails_helper"

RSpec.describe "Api::V1::ComplaintWebhooks", type: :request do
  let(:booking) { create(:booking) }

  describe "POST /create" do
    it "creates a complaint request without a status" do
      post "/api/v1/complaint_webhooks", params: {
        booking_token: booking.confirmation_token,
        date: "2026-04-14",
        complaint: "Air conditioning not cold and towel is missing"
      }

      expect(response).to have_http_status(:success)
      expect(booking.reload.complaint_requests.count).to eq(1)

      complaint = booking.complaint_requests.first
      expect(complaint.complaint_details).to include("Air conditioning not cold")
      expect(complaint.requested_at.to_date.iso8601).to eq("2026-04-14")
    end
  end
end
