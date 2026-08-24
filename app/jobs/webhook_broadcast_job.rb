# frozen_string_literal: true

# Deciding who hears about something, and handing each of them to their own
# delivery job.
#
# Fan-out only: nothing is posted from here. One endpoint being down must not
# cost the others a repeat, and one slow endpoint must not hold up the rest --
# both of which follow from each delivery being its own retryable unit.
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
      WebhookDeliveryJob.perform_later(endpoint.url, endpoint.name, event_type, payload)
    end

    # The single URL that predates the endpoints table. It has no hotel and no
    # event list to give it, so it behaves exactly like an unscoped endpoint
    # and keeps receiving everything. Narrowing it is a migration of its own --
    # move it into `webhook_endpoints`, where it can be scoped like the rest.
    legacy_url = AppConfig.get("webhook_url")
    return if legacy_url.blank? || endpoints.any? { |endpoint| endpoint.url == legacy_url }

    WebhookDeliveryJob.perform_later(legacy_url, "Legacy Webhook", event_type, payload)
  end
end
