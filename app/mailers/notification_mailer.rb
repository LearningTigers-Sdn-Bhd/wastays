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

  def check_out_receipt_message(delivery)
    assign_delivery(delivery)

    mail(
      to: @booking.guest_email,
      subject: "Your checkout invoice from #{@payload[:hotel_name]}"
    )
  end

  def in_stay_guest_messaging(delivery)
    assign_delivery(delivery)

    rule_subject = case @payload[:rule_key].to_s
    when "mid_stay"
      "How is your stay going at #{@payload[:hotel_name]}?"
    when "upsell"
      "Make your stay even better at #{@payload[:hotel_name]}"
    else
      "Things to do before checkout at #{@payload[:hotel_name]}"
    end

    mail(
      to: @booking.guest_email,
      subject: rule_subject
    )
  end

  def invoice_package(delivery)
    assign_delivery(delivery)
    group = Notifications::InvoiceDelivery.load!(delivery:)
    pdf = Reports::Bookings::GenerateCombinedInvoices.new(
      hotel: delivery.hotel,
      invoices: group.invoices,
      recipient: group.recipient,
      printed_by: @payload[:requested_by_name]
    ).generate
    attachments["combined-invoices-#{@booking.confirmation_token}.pdf"] = {
      mime_type: "application/pdf",
      content: pdf
    }

    mail(
      to: @payload.fetch(:recipient_email),
      subject: "Your invoices from #{@payload[:hotel_name]}"
    )
  end

  # Links to the guest's own copy of the card rather than attaching a
  # generated PDF: the guest can review, sign, and download it themselves once
  # signed, and the send no longer depends on PDF rendering succeeding inside
  # a background job to reach the guest at all.
  def guest_registration_card(delivery)
    assign_delivery(delivery)
    @card = find_guest_registration_card
    @card_url = guest_registration_card_url(@card.public_token)
    @nights = (@booking.check_out.to_date - @booking.check_in.to_date).to_i

    mail(
      to: @payload.fetch(:recipient_email),
      subject: "Your guest registration card — #{@booking.confirmation_token}"
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

  def find_guest_registration_card
    card_id = @payload[:guest_registration_card_id]
    if card_id.present?
      card = GuestRegistrationCard.find_by(id: card_id)
      return card if card
    end

    booking_guest_id = @payload[:booking_guest_id]
    if booking_guest_id.present?
      bg = @booking.booking_guests.find { |g| g.id.to_s == booking_guest_id.to_s }
      return bg.guest_registration_card if bg&.guest_registration_card
    end

    primary = @booking.booking_guests.find(&:primary?)
    primary&.guest_registration_card || @booking.guest_registration_cards.find_by(booking_guest_id: nil) || @booking.guest_registration_card
  end
end
