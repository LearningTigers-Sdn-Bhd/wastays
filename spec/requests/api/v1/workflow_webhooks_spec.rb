require 'rails_helper'

RSpec.describe "Api::V1::WorkflowWebhooks", type: :request do
  let(:booking) { create(:booking) }
  let!(:pre_checkin) { create(:pre_checkin, booking: booking) }

  describe "POST /create" do
    it "returns http success" do
      post "/api/v1/workflow_webhooks", params: { booking_token: booking.confirmation_token, event_type: "flow_started" }
      expect(response).to have_http_status(:success)
    end
  end
end
