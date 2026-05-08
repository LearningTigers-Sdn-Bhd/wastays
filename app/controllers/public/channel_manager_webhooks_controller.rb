require "active_support/security_utils"

module Public
  class ChannelManagerWebhooksController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

    def channex
      return head :unauthorized unless webhook_authorized?

      # Channel Manager sends a POST request
      # Payload: { "id": "...", "event": "booking.created", "payload": { "revision_id": "...", "property_id": "..." } }

      payload = JSON.parse(request.body.read)
      event_type = payload["event"]

      if event_type.start_with?("booking.")
        revision_id = payload.dig("payload", "revision_id")
        property_id = payload.dig("payload", "property_id")

        # Find local hotel by external ID
        mapping = ChannelMapping.find_by(provider: "channex", external_id: property_id, mappable_type: "Hotel")

        if mapping
          ChannelManagers::IngestRevisionJob.perform_later(mapping.mappable_id, revision_id)
          head :ok
        else
          # Hotel not found in our system
          head :not_found
        end
      else
        # Other event types we might not care about yet
        head :ok
      end
    rescue => e
      Rails.logger.error "Channel Manager Webhook Error: #{e.message}"
      head :internal_server_error
    end

    private

    def webhook_authorized?
      expected_token = AppConfig.get("channex_webhook_token").to_s
      return true if expected_token.blank?

      provided_token = request.headers["X-Channex-Webhook-Token"].to_s
      return false if provided_token.blank?
      return false unless provided_token.bytesize == expected_token.bytesize

      ActiveSupport::SecurityUtils.secure_compare(provided_token, expected_token)
    end
  end
end
