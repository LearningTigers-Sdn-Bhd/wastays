require 'rails_helper'

RSpec.describe "Public::ChannelManagerWebhooks", type: :request do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let!(:hotel_mapping) { create(:channel_mapping, mappable: hotel, provider: "channex", external_id: "ch_prop_123") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let!(:rt_mapping) { create(:channel_mapping, mappable: room_type, provider: "channex", external_id: "ch_rt_123") }
  let(:rate_plan) { create(:rate_plan, room_type: room_type) }
  let!(:rp_mapping) { create(:channel_mapping, mappable: rate_plan, provider: "channex", external_id: "ch_rp_123") }

  describe "POST /public/webhooks/channex" do
    let(:payload) do
      {
        id: "evt_123",
        event: "booking.created",
        payload: {
          revision_id: "rev_123",
          property_id: "ch_prop_123"
        }
      }
    end

    it "enqueues an IngestRevisionJob" do
      expect {
        post "/webhooks/channex", params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      }.to have_enqueued_job(ChannelManagers::IngestRevisionJob).with(hotel.id, "rev_123")

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 if hotel mapping is not found" do
      bad_payload = payload.deep_merge(payload: { property_id: "unknown" })
      post "/webhooks/channex", params: bad_payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
