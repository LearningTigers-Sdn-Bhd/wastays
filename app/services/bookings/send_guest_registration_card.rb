# frozen_string_literal: true

module Bookings
  # Emails a guest their registration card on request from the front desk.
  # Sending rides the notification pipeline rather than a bespoke job, so it
  # inherits delivery status, retries and the training-mode hold for free.
  class SendGuestRegistrationCard
    Result = Data.define(:success?, :delivery, :recipient, :error) do
      def self.success(delivery:, recipient:)
        new(success?: true, delivery: delivery, recipient: recipient, error: nil)
      end

      def self.failure(error)
        new(success?: false, delivery: nil, recipient: nil, error: error)
      end
    end

    def self.call(booking:, user: nil, booking_guest_id: nil)
      new(booking: booking, user: user, booking_guest_id: booking_guest_id).call
    end

    def initialize(booking:, user: nil, booking_guest_id: nil)
      @booking = booking
      @user = user
      @booking_guest_id = booking_guest_id
    end

    def call
      recipient = recipient_email
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
        idempotency_key: [ @booking.hotel_id, @booking.id, "guest_registration_card", @booking_guest_id, SecureRandom.uuid ].compact_blank.join(":"),
        payload: {
          recipient_email: recipient,
          hotel_name: @booking.hotel.name,
          guest_name: recipient_name,
          requested_by_name: @user&.name
        }
      )

      Notifications::DeliverJob.perform_later(delivery.id)
      Result.success(delivery: delivery, recipient: recipient)
    end

    private

    def active_booking_guest
      if @booking_guest_id.present?
        @booking.booking_guests.find { |bg| bg.id.to_s == @booking_guest_id.to_s }
      else
        @booking.booking_guests.find(&:primary?)
      end
    end

    def recipient_email
      active_booking_guest&.email_snapshot.presence || @booking.guest_email.presence
    end

    def recipient_name
      active_booking_guest&.name_snapshot.presence || @booking.guest_name
    end

    def failure(message)
      Result.failure(message)
    end
  end
end
