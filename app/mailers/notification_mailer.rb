# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  before_action :load_delivery_context
  before_action :attach_brand_logo

  def check_in_confirmation(delivery)
    assign_delivery(delivery)

    mail(
      to: @booking.guest_email,
      subject: "Checked in at #{@payload[:hotel_name]}"
    )
  end

  def post_stay_review_request(delivery)
    assign_delivery(delivery)

    mail(
      to: @booking.guest_email,
      subject: "How was your stay at #{@payload[:hotel_name]}?"
    )
  end

  def pre_arrival_notification(delivery)
    assign_delivery(delivery)

    stage_label = @payload[:stage].to_s.upcase.presence || "D1"

    mail(
      to: @booking.guest_email,
      subject: "#{stage_label} reminder: your stay at #{@payload[:hotel_name]} is coming up"
    )
  end

  private

  def load_delivery_context
    @delivery = nil
    @booking = nil
    @payload = {}.with_indifferent_access
    @guest_first_name = "Guest"
  end

  def assign_delivery(delivery)
    @delivery = delivery
    @booking = delivery.booking
    @payload = delivery.payload.with_indifferent_access
    @guest_first_name = @payload[:guest_name].to_s.split.first.presence || "Guest"
  end

  def attach_brand_logo
    attachments.inline["long-logo.png"] = File.read(
      Rails.root.join("app/assets/images/logo/long-logo.png")
    )
  end
end
