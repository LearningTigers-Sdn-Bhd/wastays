# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# One event, one endpoint, one POST.
#
# Split out of WebhookBroadcastJob so a failure can be retried without
# re-delivering to the endpoints that already accepted it -- retrying a whole
# fan-out sends every other endpoint the same event again, which is why the
# broadcast used to swallow every error instead of retrying at all.
#
# Swallowing them is survivable for a booking confirmation the guest also gets
# by email. It is not survivable for a staff reply: the inbox shows "sent", and
# the guest gets nothing.
class WebhookDeliveryJob < ApplicationJob
  queue_as :default

  # The endpoint is reachable but broken, or it said it was. Distinct from the
  # network errors below only so the message reads honestly in the queue.
  class DeliveryFailed < StandardError; end

  NETWORK_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET,
    Errno::EHOSTUNREACH, Errno::ETIMEDOUT, SocketError, OpenSSL::SSL::SSLError, IOError
  ].freeze

  retry_on(*NETWORK_ERRORS, DeliveryFailed, wait: :polynomially_longer, attempts: 5)

  TIMEOUT = 10

  def perform(url, name, event_type, payload)
    response = post(url, event_type, payload)
    code = response.code.to_i
    return if code.between?(200, 299)

    # A refusal is not a hiccup. The endpoint understood the request and said
    # no, so sending it again unchanged gets the same no -- log it and stop
    # rather than spending five attempts proving it.
    if code.between?(400, 499)
      Rails.logger.error("[WebhookDeliveryJob] #{name} (#{url}) refused #{event_type}: HTTP #{code}")
      return
    end

    raise DeliveryFailed, "#{name} (#{url}) failed #{event_type}: HTTP #{code}"
  end

  private

  def post(url, event_type, payload)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
    request.body = {
      event: event_type,
      sent_at: Time.current.iso8601,
      data: payload
    }.to_json

    http.request(request)
  end
end
