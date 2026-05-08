# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  def check_in_confirmation(delivery)
    @delivery = delivery
    @booking = delivery.booking
    @payload = delivery.payload.with_indifferent_access
    @guest_first_name = @payload[:guest_name].to_s.split.first.presence || "Guest"

    attachments.inline["long-logo.png"] = File.read(
      Rails.root.join("app/assets/images/logo/long-logo.png")
    )

    mail(
      to: @booking.guest_email,
      subject: "Checked in at #{@payload[:hotel_name]}"
    )
  end
end
