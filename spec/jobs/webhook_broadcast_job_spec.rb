# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookBroadcastJob, type: :job do
  let(:hotel) { create(:hotel, name: "Test Hotel") }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "John Doe") }
  let(:housekeeping_request) { create(:housekeeping_request, booking: booking, status: "pending") }
  let(:complaint_request) { create(:complaint_request, booking: booking, status: "pending") }
  let!(:webhook_endpoint) { create(:webhook_endpoint, name: "Test Endpoint", url: "https://example.com/webhook", enabled: true) }

  before do
    # Mock Net::HTTP to avoid actual network calls
    allow(Net::HTTP).to receive(:new).and_return(instance_double(Net::HTTP, "use_ssl=" => true, "open_timeout=" => true, "read_timeout=" => true, "request" => double(code: "200")))
  end

  describe "triggering from StatusUpdater" do
    it "broadcasts housekeeping_completed when housekeeping is finished" do
      expect {
        HotelPortal::Requests::StatusUpdater.new(
          hotel: hotel,
          kind: :housekeeping,
          request_id: housekeeping_request.id,
          status: :completed
        ).call
      }.to have_enqueued_job(WebhookBroadcastJob).with("housekeeping_completed", anything)
    end

    it "broadcasts complaint_resolved when complaint is resolved" do
      expect {
        HotelPortal::Requests::StatusUpdater.new(
          hotel: hotel,
          kind: :complaint,
          request_id: complaint_request.id,
          status: :completed # Maps to resolved
        ).call
      }.to have_enqueued_job(WebhookBroadcastJob).with("complaint_resolved", anything)
    end

    it "does not broadcast if status is not 'done'" do
      expect {
        HotelPortal::Requests::StatusUpdater.new(
          hotel: hotel,
          kind: :housekeeping,
          request_id: housekeeping_request.id,
          status: :in_progress
        ).call
      }.not_to have_enqueued_job(WebhookBroadcastJob)
    end
  end

  describe "execution" do
    it "posts to enabled endpoints" do
      payload = { foo: "bar" }
      
      # We already mocked Net::HTTP in before block
      # Just ensuring perform doesn't crash and respects enabled flag
      expect_any_instance_of(WebhookBroadcastJob).to receive(:post_to_webhook).with("https://example.com/webhook", "Test Endpoint", "test_event", payload)
      
      WebhookBroadcastJob.new.perform("test_event", payload)
    end

    it "does not post to disabled endpoints" do
      webhook_endpoint.update(enabled: false)
      expect_any_instance_of(WebhookBroadcastJob).not_to receive(:post_to_webhook)
      
      WebhookBroadcastJob.new.perform("test_event", { foo: "bar" })
    end
  end
end
