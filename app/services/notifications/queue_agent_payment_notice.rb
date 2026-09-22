# frozen_string_literal: true

module Notifications
  # Records and sends one agent payment mail, through the same
  # notification_deliveries table every other message in the product uses.
  #
  # The point of routing these through deliveries rather than calling a mailer
  # directly is the record. An agent whose rooms were released will ask whether
  # they were warned, and the answer has to be a row, not a log line -- including
  # when there was nobody to write to, which is recorded as `skipped` rather than
  # passing silently.
  #
  # `idempotency_key` is the caller's, because only the caller knows what "the
  # same message twice" means: for a reminder it is the offset and the deadline,
  # for an approval it is the submission.
  class QueueAgentPaymentNotice
    CHANNEL = "email"

    Result = Struct.new(:delivery, :sent, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(booking:, notification_type:, trigger_event:, idempotency_key:, extra: {})
      @booking = booking
      @notification_type = notification_type
      @trigger_event = trigger_event
      @idempotency_key = idempotency_key
      @extra = extra
    end

    def call
      delivery = NotificationDelivery.find_or_initialize_by(idempotency_key: @idempotency_key)
      # Already recorded by an earlier run. Sending again is the thing this
      # method exists to prevent.
      return Result.new(delivery: delivery, sent: false) if delivery.persisted?

      payload = PayloadBuilders::AgentPaymentNotice.new(
        booking: @booking,
        notification_type: @notification_type,
        trigger_event: @trigger_event,
        extra: @extra
      ).call

      deliverable = payload[:recipient_email].present?
      delivery.assign_attributes(
        hotel: @booking.hotel,
        booking: @booking,
        notification_type: @notification_type,
        channel: CHANNEL,
        trigger_event: @trigger_event,
        status: deliverable ? "pending" : "skipped",
        error_message: deliverable ? nil : "The agency has no contact email on file.",
        payload: payload
      )
      delivery.save!

      DeliverJob.perform_later(delivery.id) if deliverable
      Result.new(delivery: delivery, sent: deliverable)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
      # Two workers reached the same key together; the loser has nothing to do.
      # The model validates the key as well as indexing it, so the race can
      # surface either way round depending on which check loses.
      existing = NotificationDelivery.find_by(idempotency_key: @idempotency_key)
      raise error if existing.blank?

      Result.new(delivery: existing, sent: false)
    end
  end
end
