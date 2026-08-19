# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

class WebhookBroadcastJob < ApplicationJob
  queue_as :default

  # `hotel_id` says whose event this is. Without it only platform-wide
  # endpoints are reached, because an event nobody has claimed should not be
  # handed to a relay that serves one hotel.
  #
  # It is a keyword with a default so the queue can drain jobs enqueued by the
  # old signature during a deploy; every caller in the app now passes it.
  def perform(event_type, payload, hotel_id: nil)
    endpoints = WebhookEndpoint.listening_for(event_type, hotel_id: hotel_id)

    endpoints.each do |endpoint|
      post_to_webhook(endpoint.url, endpoint.name, event_type, payload)
    end

    # The single URL that predates the endpoints table. It has no hotel and no
    # event list to give it, so it behaves exactly like an unscoped endpoint
    # and keeps receiving everything. Narrowing it is a migration of its own --
    # move it into `webhook_endpoints`, where it can be scoped like the rest.
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
