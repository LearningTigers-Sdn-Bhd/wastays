# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

class WebhookBroadcastJob < ApplicationJob
  queue_as :default

  # event_type: "housekeeping_completed", "complaint_resolved", "booking_confirmed", etc.
  # payload: Hash containing the data to send
  def perform(event_type, payload)
    endpoints = WebhookEndpoint.where(enabled: true)
    
    # 1. New Multi-Webhook System
    endpoints.each do |endpoint|
      # If we want to filter by event_types later, we can add it here
      post_to_webhook(endpoint.url, endpoint.name, event_type, payload)
    end

    # 2. Legacy Fallback (if any)
    legacy_url = AppConfig.get("webhook_url")
    if legacy_url.present? && endpoints.none? { |e| e.url == legacy_url }
      post_to_webhook(legacy_url, "Legacy Webhook", event_type, payload)
    end
  end

  private

  def post_to_webhook(url, name, event_type, payload)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10

    full_payload = {
      event: event_type,
      sent_at: Time.current.iso8601,
      data: payload
    }

    request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
    request.body = full_payload.to_json
    
    response = http.request(request)
    
    unless response.code.to_i.between?(200, 299)
      Rails.logger.error("[WebhookBroadcastJob] Failed to post #{event_type} to #{name} (#{url}): HTTP #{response.code}")
    end
  rescue => e
    Rails.logger.error("[WebhookBroadcastJob] Error posting #{event_type} to #{name} (#{url}): #{e.message}")
  end
end
