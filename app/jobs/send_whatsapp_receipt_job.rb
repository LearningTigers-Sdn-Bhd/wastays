# frozen_string_literal: true

class SendWhatsappReceiptJob < ApplicationJob
  queue_as :default

  def perform(booking_id)
    booking = Booking.find_by(id: booking_id)
    return unless booking

    payload = build_payload(booking)
    WebhookBroadcastJob.perform_now("booking_confirmed", payload)
  end

  private

  def build_payload(booking)
    nights = (booking.check_out.to_date - booking.check_in.to_date).to_i
    host_options = Rails.application.config.action_mailer.default_url_options || {}

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
      receipt_url: Rails.application.routes.url_helpers.confirmation_booking_url(
        booking.confirmation_token,
        host: host_options[:host],
        protocol: host_options[:protocol] || "https"
      )
    }
  end
end
