require "active_support/security_utils"

module Public
  class ChannelManagerWebhooksController < ApplicationController
    # `booking` fires for every revision; the other three are the per-status
    # variants Channex lets you subscribe to instead.
    BOOKING_EVENTS = %w[booking booking_new booking_modification booking_cancellation].freeze
    NON_ACKED_BOOKING_EVENT = "non_acked_booking"

    # Reported when Channex says a revision went 30 minutes without an ack.
    UnackedRevisionError = Class.new(StandardError)

    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

    def channex
      return head :unauthorized unless webhook_authorized?

      payload = JSON.parse(request.body.read)
      event_type = payload["event"].to_s

      if BOOKING_EVENTS.include?(event_type)
        enqueue_revision(payload)
      elsif event_type == NON_ACKED_BOOKING_EVENT
        report_non_acked_booking(payload)
      else
        # Other event types we might not care about yet
        head :ok
      end
    rescue => e
      Rails.logger.error "Channel Manager Webhook Error: #{e.message}"
      head :internal_server_error
    end

    private

    # Payload: { "event": "booking", "payload": { "revision_id": "...", "property_id": "..." } }
    def enqueue_revision(payload)
      revision_id = payload.dig("payload", "revision_id") || payload["id"]
      property_id = payload.dig("payload", "property_id") || payload["property_id"]

      mapping = hotel_mapping_for(property_id)
      # Hotel not found in our system
      return head :not_found unless mapping

      if revision_id.present?
        ChannelManagers::IngestRevisionJob.perform_later(mapping.mappable_id, revision_id)
      else
        # If no revision_id, it's likely a notification to check the feed
        # We can trigger PullRevisionsJob which handles all properties
        ChannelManagers::PullRevisionsJob.perform_later
      end
      head :ok
    end

    # Channex sends this when a revision is still unacknowledged 30 minutes after
    # first delivery, which is the point it stops being re-served. Surface it,
    # then try the revision once more while it can still be fetched by id.
    def report_non_acked_booking(payload)
      data = payload["payload"] || {}
      revision_id = data["booking_revision_id"]
      mapping = hotel_mapping_for(data["property_id"] || payload["property_id"])
      return head :ok unless mapping

      Rails.error.report(
        UnackedRevisionError.new("Channex revision #{revision_id} was not acknowledged within 30 minutes"),
        handled: true,
        severity: :error,
        context: {
          hotel_id: mapping.mappable_id,
          revision_id: revision_id,
          booking_unique_id: data["booking_unique_id"],
          ota_code: data["ota_code"],
          operation: "channex_non_acked_booking"
        }
      )
      ChannelManagers::IngestRevisionJob.perform_later(mapping.mappable_id, revision_id) if revision_id.present?
      head :ok
    end

    def hotel_mapping_for(property_id)
      ChannelMapping.find_by(provider: "channex", external_id: property_id, mappable_type: "Hotel")
    end

    def webhook_authorized?
      expected_token = AppConfig.get("channex_webhook_token").to_s
      # An unset token is only tolerated on a developer machine or in tests.
      return Rails.env.local? if expected_token.blank?

      provided_token = request.headers["X-Channex-Webhook-Token"].to_s
      return false if provided_token.blank?
      return false unless provided_token.bytesize == expected_token.bytesize

      ActiveSupport::SecurityUtils.secure_compare(provided_token, expected_token)
    end
  end
end
