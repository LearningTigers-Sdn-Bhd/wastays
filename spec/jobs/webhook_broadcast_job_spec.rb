# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookBroadcastJob, type: :job do
  let(:hotel) { create(:hotel, name: "Test Hotel") }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "John Doe") }
  let(:housekeeping_request) { create(:housekeeping_request, booking: booking, status: "pending") }
  let(:complaint_request) { create(:complaint_request, booking: booking, status: "pending") }
  let!(:webhook_endpoint) { create(:webhook_endpoint, name: "Test Endpoint", url: "https://example.com/webhook", enabled: true) }


  describe "triggering from StatusUpdater" do
    it "broadcasts housekeeping_completed when housekeeping is finished" do
      expect {
        HotelPortal::Requests::StatusUpdater.new(
          hotel: hotel,
          kind: :housekeeping,
          request_id: housekeeping_request.id,
          status: :completed
        ).call
      }.to have_enqueued_job(WebhookBroadcastJob).with("housekeeping_completed", anything, hotel_id: hotel.id)
    end

    it "broadcasts complaint_resolved when complaint is resolved" do
      expect {
        HotelPortal::Requests::StatusUpdater.new(
          hotel: hotel,
          kind: :complaint,
          request_id: complaint_request.id,
          status: :completed # Maps to resolved
        ).call
      }.to have_enqueued_job(WebhookBroadcastJob).with("complaint_resolved", anything, hotel_id: hotel.id)
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
    let(:payload) { { foo: "bar" } }
    let(:other_hotel) { create(:hotel, name: "Other Hotel") }

    it "posts to enabled endpoints" do
      expect {
        WebhookBroadcastJob.new.perform("test_event", payload)
      }.to have_enqueued_job(WebhookDeliveryJob).with("https://example.com/webhook", "Test Endpoint", "test_event", payload)
    end

    it "does not post to disabled endpoints" do
      webhook_endpoint.update(enabled: false)
      expect {
        WebhookBroadcastJob.new.perform("test_event", payload)
      }.not_to have_enqueued_job(WebhookDeliveryJob)
    end

    it "reaches an endpoint pinned to the hotel the event belongs to" do
      webhook_endpoint.update!(hotel: hotel)

      expect {
        WebhookBroadcastJob.new.perform("booking_confirmed", payload, hotel_id: hotel.id)
      }.to have_enqueued_job(WebhookDeliveryJob).with("https://example.com/webhook", "Test Endpoint", "booking_confirmed", payload)
    end

    it "keeps one hotel's events away from another hotel's endpoint" do
      webhook_endpoint.update!(hotel: other_hotel)

      expect {
        WebhookBroadcastJob.new.perform("booking_confirmed", payload, hotel_id: hotel.id)
      }.not_to have_enqueued_job(WebhookDeliveryJob)
    end

    it "keeps a hotel's endpoint out of a broadcast that names no hotel" do
      webhook_endpoint.update!(hotel: hotel)

      expect {
        WebhookBroadcastJob.new.perform("booking_confirmed", payload)
      }.not_to have_enqueued_job(WebhookDeliveryJob)
    end

    it "reaches a platform-wide endpoint whichever hotel the event belongs to" do
      expect {
        WebhookBroadcastJob.new.perform("booking_confirmed", payload, hotel_id: other_hotel.id)
      }.to have_enqueued_job(WebhookDeliveryJob).with("https://example.com/webhook", "Test Endpoint", "booking_confirmed", payload)
    end

    it "sends only the events an endpoint asked for" do
      webhook_endpoint.update!(event_types: [ "booking_confirmed" ])

      expect {
        WebhookBroadcastJob.new.perform("complaint_resolved", payload)
      }.not_to have_enqueued_job(WebhookDeliveryJob)
    end

    it "sends every event to an endpoint that named none" do
      expect {
        WebhookBroadcastJob.new.perform("complaint_resolved", payload)
      }.to have_enqueued_job(WebhookDeliveryJob).with("https://example.com/webhook", "Test Endpoint", "complaint_resolved", payload)
    end
  end
end
