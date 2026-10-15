# frozen_string_literal: true

require "net/http"
require "json"
require "base64"

# ActionMailer delivery method for MillionSend (Resend-compatible REST API).
#   config.action_mailer.delivery_method = :million_send
#   config.action_mailer.million_send_settings = { api_key: ENV["MILLIONSEND_API_KEY"] }
class MillionSendDelivery
  class DeliveryError < StandardError; end

  DEFAULT_BASE_URL = "https://email-api.jesseltonpixel.com"

  attr_reader :settings

  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    response = post_json("/emails", payload_for(mail))
    return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

    raise DeliveryError, "MillionSend #{response.code}: #{response.body.to_s.truncate(300)}"
  end

  private

  def payload_for(mail)
    {
      from: addresses(mail, :from).first,
      to: addresses(mail, :to).presence,
      cc: addresses(mail, :cc).presence,
      bcc: addresses(mail, :bcc).presence,
      reply_to: addresses(mail, :reply_to).presence,
      subject: mail.subject,
      html: body_for(mail, "text/html"),
      text: body_for(mail, "text/plain"),
      attachments: attachments_for(mail).presence
    }.compact
  end

  # "Name <a@b.com>" when the header parses, plain addresses when it doesn't.
  def addresses(mail, field)
    header = mail[field]
    return [] unless header

    header.respond_to?(:formatted) ? header.formatted : Array(mail.public_send(field))
  end

  def body_for(mail, type)
    return mail.decoded if !mail.multipart? && (mail.mime_type || "text/plain") == type

    mail.find_first_mime_type(type)&.decoded
  end

  def attachments_for(mail)
    mail.attachments.map do |a|
      {
        filename: a.filename,
        content: Base64.strict_encode64(a.body.decoded),
        content_type: a.mime_type,
        content_id: (a.inline? ? a.content_id.to_s.delete("<>").presence : nil)
      }.compact
    end
  end

  def post_json(path, body)
    uri = URI.join(settings.fetch(:base_url, DEFAULT_BASE_URL), path)
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json",
                                        "Authorization" => "Bearer #{settings.fetch(:api_key)}")
    request.body = body.to_json
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) do |http|
      http.request(request)
    end
  end
end
