require "net/http"
require "uri"
require "json"

class SendWhatsappInvoiceJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    url = AppConfig.get("webhook_url")
    unless url.present?
      Rails.logger.warn("[SendWhatsappInvoiceJob] No webhook URL configured — skipping booking #{booking_id}")
      return
    end

    payload = build_payload(booking)
    post_to_webhook(url, payload)
  end

  private

  def build_payload(booking)
    nights = (booking.check_out - booking.check_in).to_i

    {
      confirmation_token: booking.confirmation_token,
      guest_name: booking.guest_name,
      guest_phone: booking.guest_phone,
      guest_email: booking.guest_email,
      hotel_name: booking.hotel.name,
      check_in: booking.check_in.strftime("%Y-%m-%d"),
      check_out: booking.check_out.strftime("%Y-%m-%d"),
      nights: nights,
      total_amount: format("%.2f", booking.total_amount.to_f),
      currency: booking.currency,
      invoice_url: invoice_url_for(booking)
    }
  end

  def invoice_url_for(booking)
    host_options = Rails.application.config.action_mailer.default_url_options || {}

    Rails.application.routes.url_helpers.invoice_booking_url(
      booking.confirmation_token,
      host: host_options[:host],
      protocol: host_options[:protocol] || "https"
    )
  end

  def post_to_webhook(url, payload)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
    request.body = payload.to_json
    http.request(request)
  end
end
