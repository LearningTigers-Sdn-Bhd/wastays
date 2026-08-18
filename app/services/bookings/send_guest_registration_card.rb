# frozen_string_literal: true

require "ostruct"

module Bookings
  # Emails a guest their registration card on request from the front desk.
  # Sending rides the notification pipeline rather than a bespoke job, so it
  # inherits delivery status, retries and the training-mode hold for free.
  class SendGuestRegistrationCard
    def self.call(booking:, user: nil)
      new(booking: booking, user: user).call
    end

    def initialize(booking:, user: nil)
      @booking = booking
      @user = user
    end

    def call
      recipient = @booking.guest_email.presence
      return failure("This booking has no guest email address to send to.") if recipient.blank?

      card = @booking.guest_registration_card
      return failure("The registration card has not been created yet.") if card.blank?
      return failure("Set a Terms & Conditions policy in Settings before sending this card.") unless card.ready_for_guest?

      delivery = NotificationDelivery.create!(
        hotel: @booking.hotel,
        booking: @booking,
        notification_type: "guest_registration_card",
        channel: "email",
        trigger_event: "manual",
        status: "pending",
        # Staff may legitimately send the card more than once — a guest loses the
        # mail, an address is corrected — so each request is its own delivery.
        idempotency_key: [ @booking.hotel_id, @booking.id, "guest_registration_card", SecureRandom.uuid ].join(":"),
        payload: {
          recipient_email: recipient,
          hotel_name: @booking.hotel.name,
          guest_name: @booking.guest_name,
          requested_by_name: @user&.name
        }
      )

      Notifications::DeliverJob.perform_later(delivery.id)
      OpenStruct.new(success?: true, delivery: delivery, recipient: recipient)
    end

    private

    def failure(message)
      OpenStruct.new(success?: false, error: message)
    end
  end
end
