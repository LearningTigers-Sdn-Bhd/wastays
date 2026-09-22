# frozen_string_literal: true

module Notifications
  # The hotel's side of the agent payment path, on the existing staff bell.
  #
  # Two moments the desk cannot afford to learn about from a guest: a slip is
  # waiting to be reviewed -- the agent's clock is stopped while it sits there,
  # so an unreviewed queue costs the hotel the sale it is holding -- and rooms
  # were released automatically for non-payment, which is a reservation
  # disappearing without anyone touching it.
  #
  # Modelled on NightAudits::PublishStaffNotification: one row per recipient,
  # keyed for deduplication, and a failure to publish never takes down whatever
  # caused it.
  class PublishAgentPaymentStaffNotification
    PERMISSION = "manage_ar_payments"

    EVENTS = {
      submitted: {
        notification_type: "agent_payment_submitted",
        severity: "info",
        title: "An agent sent a payment slip"
      },
      released: {
        notification_type: "agent_booking_released",
        severity: "warning",
        title: "Rooms released for non-payment"
      }
    }.freeze

    def self.call(...) = new(...).call

    def initialize(booking:, event:, submission: nil)
      @booking = booking
      @event = event.to_sym
      @submission = submission
      @hotel = booking&.hotel
    end

    def call
      return false if @hotel.blank? || !EVENTS.key?(@event)

      recipients.find_each { |access| publish_for(access.user) }
      true
    rescue StandardError => error
      log_failure(error)
      false
    end

    private

    def recipients
      @hotel.user_hotel_accesses.active
        .joins(role: :permissions)
        .includes(:user)
        .where(permissions: { slug: PERMISSION })
        .distinct
    end

    def publish_for(user, retried: false)
      key = deduplication_key(user)
      notification = StaffNotification.find_or_initialize_by(deduplication_key: key)
      notification.assign_attributes(attributes_for(user))
      notification.save!
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
      # Two callers can reach the same key together. One retry, then give up.
      return log_failure(error, user:) if retried || !StaffNotification.exists?(deduplication_key: key)

      publish_for(user, retried: true)
    rescue StandardError => error
      log_failure(error, user:)
    end

    def attributes_for(user)
      event = EVENTS.fetch(@event)

      {
        hotel: @hotel,
        recipient: user,
        subject: @booking,
        notification_type: event.fetch(:notification_type),
        severity: event.fetch(:severity),
        title: event.fetch(:title),
        message: message,
        action_path: action_path,
        metadata: {
          "booking_id" => @booking.id,
          "agency" => @booking.hotel_corporate_account&.corporate_account&.name,
          "submission_id" => @submission&.id
        }.compact,
        resolved_at: nil
      }
    end

    def message
      agency = @booking.hotel_corporate_account&.corporate_account&.name.presence || "An agency"

      case @event
      when :submitted
        "#{agency} sent a transfer slip for #{@booking.formatted_reservation_number}. " \
          "Their payment deadline is paused until it is reviewed."
      else
        "#{@booking.formatted_reservation_number} was cancelled and its rooms returned to sale: " \
          "#{agency} did not pay by the deadline."
      end
    end

    # Straight to the thing that needs doing. A slip is reviewed on the payment
    # screen; a released booking is read on the reservation.
    def action_path
      routes = Rails.application.routes.url_helpers

      if @event == :submitted && @submission.present?
        routes.new_hotel_ar_payment_path(@hotel, ar_payment_submission_id: @submission.id)
      else
        routes.hotel_booking_path(@hotel, @booking)
      end
    rescue StandardError
      nil
    end

    def log_failure(error, user: nil)
      recipient = user ? " recipient #{user.id}" : ""
      Rails.logger.error(
        "Failed to publish agent payment staff notification for booking #{@booking&.id}#{recipient}: #{error.message}"
      )
    end

    def deduplication_key(user)
      base = @event == :submitted ? "submission:#{@submission&.id}" : "release:#{@booking.id}"
      "agent_payment:#{@event}:#{base}:recipient:#{user.id}"
    end
  end
end
