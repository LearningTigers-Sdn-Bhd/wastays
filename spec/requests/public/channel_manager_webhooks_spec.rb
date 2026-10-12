require 'rails_helper'

RSpec.describe "Public::ChannelManagerWebhooks", type: :request do
  let(:hotel) { create(:hotel, preferred_channel_manager: "channex") }
  let!(:hotel_mapping) { create(:channel_mapping, mappable: hotel, provider: "channex", external_id: "ch_prop_123") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let!(:rt_mapping) { create(:channel_mapping, mappable: room_type, provider: "channex", external_id: "ch_rt_123") }
  let(:rate_plan) { create(:rate_plan, room_type: room_type) }
  let!(:rp_mapping) { create(:channel_mapping, mappable: rate_plan, provider: "channex", external_id: "ch_rp_123") }

  describe "POST /public/webhooks/channex" do
    let(:json_headers) { { "CONTENT_TYPE" => "application/json" } }
    let(:payload) do
      {
        event: "booking",
        payload: {
          revision_id: "rev_123",
          property_id: "ch_prop_123"
        }
      }
    end

    def post_webhook(body, headers = json_headers)
      post "/webhooks/channex", params: body.to_json, headers: headers
    end

    it "enqueues an IngestRevisionJob" do
      allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return(nil)

      expect {
        post_webhook(payload)
      }.to have_enqueued_job(ChannelManagers::IngestRevisionJob).with(hotel.id, "rev_123")

      expect(response).to have_http_status(:ok)
    end

    %w[booking_new booking_modification booking_cancellation].each do |event|
      it "enqueues an IngestRevisionJob for #{event}" do
        allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return(nil)

        expect {
          post_webhook(payload.merge(event: event))
        }.to have_enqueued_job(ChannelManagers::IngestRevisionJob).with(hotel.id, "rev_123")

        expect(response).to have_http_status(:ok)
      end
    end

    it "ignores events it does not handle" do
      allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return(nil)

      expect {
        post_webhook(payload.merge(event: "ari"))
      }.not_to have_enqueued_job(ChannelManagers::IngestRevisionJob)

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 if hotel mapping is not found" do
      allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return(nil)

      bad_payload = payload.deep_merge(payload: { property_id: "unknown" })
      post_webhook(bad_payload)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 when webhook token does not match" do
      allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return("expected-token")

      post_webhook(payload, json_headers.merge("X-Channex-Webhook-Token" => "wrong-token"))

      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts webhook when token matches" do
      allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return("expected-token")

      expect {
        post_webhook(payload, json_headers.merge("X-Channex-Webhook-Token" => "expected-token"))
      }.to have_enqueued_job(ChannelManagers::IngestRevisionJob).with(hotel.id, "rev_123")

      expect(response).to have_http_status(:ok)
    end

    context "when no webhook token is configured in production" do
      before do
        allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return("")
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
      end

      it "rejects the request and enqueues nothing" do
        expect {
          post_webhook(payload)
        }.not_to have_enqueued_job(ChannelManagers::IngestRevisionJob)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe "non_acked_booking" do
      let(:non_acked_payload) do
        {
          event: "non_acked_booking",
          property_id: "ch_prop_123",
          payload: {
            booking_revision_id: "rev_stuck",
            property_id: "ch_prop_123",
            booking_unique_id: "BDC-111111",
            ota_code: "111111"
          }
        }
      end

      before { allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return(nil) }

      it "reports the stuck revision and retries ingesting it" do
        expect(Rails.error).to receive(:report).with(
          an_instance_of(Public::ChannelManagerWebhooksController::UnackedRevisionError),
          hash_including(
            handled: true,
            severity: :error,
            context: hash_including(hotel_id: hotel.id, revision_id: "rev_stuck", booking_unique_id: "BDC-111111")
          )
        )

        expect {
          post_webhook(non_acked_payload)
        }.to have_enqueued_job(ChannelManagers::IngestRevisionJob).with(hotel.id, "rev_stuck")

        expect(response).to have_http_status(:ok)
      end

      it "does nothing for a property we do not manage" do
        expect(Rails.error).not_to receive(:report)

        expect {
          post_webhook(non_acked_payload.deep_merge(property_id: "unknown", payload: { property_id: "unknown" }))
        }.not_to have_enqueued_job(ChannelManagers::IngestRevisionJob)

        expect(response).to have_http_status(:ok)
      end
    end

    describe "alerts Channex wants a person to look at" do
      before { allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return(nil) }

      it "reports a booking Channex could not map to our rooms" do
        expect(Rails.error).to receive(:report).with(
          an_instance_of(Public::ChannelManagerWebhooksController::ChannelAlertError),
          hash_including(context: hash_including(hotel_id: hotel.id, event: "booking_unmapped_room", revision_id: "rev_9"))
        )

        post_webhook(event: "booking_unmapped_room", property_id: "ch_prop_123", payload: { booking_id: "b_9", booking_revision_id: "rev_9" })

        expect(response).to have_http_status(:ok)
      end

      %w[booking_unmapped_rate sync_error rate_error].each do |event|
        it "reports #{event}" do
          expect(Rails.error).to receive(:report).with(
            an_instance_of(Public::ChannelManagerWebhooksController::ChannelAlertError),
            hash_including(context: hash_including(event: event))
          )

          post_webhook(event: event, property_id: "ch_prop_123", payload: { channel_name: "Agoda", error_type: "general_error" })

          expect(response).to have_http_status(:ok)
        end
      end
    end

    it "answers 400 to a body that isn't JSON, so Channex stops resending it" do
      allow(AppConfig).to receive(:get).with("channex_webhook_token").and_return(nil)

      post "/webhooks/channex", params: "{not json", headers: json_headers

      expect(response).to have_http_status(:bad_request)
    end
  end
end
