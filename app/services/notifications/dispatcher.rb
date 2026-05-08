# frozen_string_literal: true

module Notifications
  class Dispatcher
    EVENT_TO_NOTIFICATION_TYPE = {
      booking_confirmed: "pre_arrival_notification",
      booking_checked_in: "check_in_confirmation",
      booking_completed: %w[post_stay_review_request check_out_receipt_message],
      booking_updated: "pre_arrival_notification"
    }.freeze

    def initialize(event:, booking:)
      @event = event.to_sym
      @booking = booking
    end

    def call
      notification_types = Array(EVENT_TO_NOTIFICATION_TYPE.fetch(@event))
      if notification_types == [ "pre_arrival_notification" ]
        return dispatch_pre_arrival(@event)
      end

      notification_types.flat_map do |notification_type|
        config = NotificationConfig.find_by(hotel: @booking.hotel, notification_type: notification_type)
        next [] unless config&.enabled?

        payload, payload_error = payload_with_error(notification_type, config)
        Array(config.channels).map do |channel|
          create_delivery(
            notification_type:,
            channel: channel.to_s,
            payload: payload,
            config:,
            payload_error:
          )
        end.compact
      end
    end

    private

    def dispatch_pre_arrival(event)
      scheduler = Notifications::PreArrivalScheduler.new(booking: @booking)
      return scheduler.reschedule_pending!(trigger_event: event.to_s) if event == :booking_updated

      scheduler.schedule!(trigger_event: event.to_s)
    end

    def payload_for(notification_type, config)
      case notification_type
      when "check_in_confirmation"
        Notifications::PayloadBuilders::CheckInConfirmation.new(booking: @booking).call
      when "post_stay_review_request"
        Notifications::PayloadBuilders::PostStayReviewRequest.new(
          booking: @booking,
          review_link: config.settings.to_h["review_link"]
        ).call
      when "check_out_receipt_message"
        Notifications::PayloadBuilders::CheckOutReceiptMessage.new(booking: @booking).call
      else
        raise ArgumentError, "Unsupported notification type: #{notification_type}"
      end
    end

    def create_delivery(notification_type:, channel:, payload:, config:, payload_error: nil)
      key = [ @booking.hotel_id, @booking.id, notification_type, channel, @event ].join(":")
      delivery = NotificationDelivery.find_or_initialize_by(idempotency_key: key)
      return if delivery.persisted?

      delivery.assign_attributes(
        hotel: @booking.hotel,
        booking: @booking,
        notification_type: notification_type,
        channel: channel,
        trigger_event: @event.to_s,
        status: payload_error.present? ? "failed" : "pending",
        payload: payload
      )
      if payload_error.present?
        delivery.failed_at = Time.current
        delivery.error_message = payload_error
      end
      delivery.save!
      schedule_delivery(delivery, config) unless payload_error.present?
      delivery
    end

    def payload_with_error(notification_type, config)
      [ payload_for(notification_type, config), nil ]
    rescue ArgumentError => e
      [ {}, e.message ]
    end

    def schedule_delivery(delivery, config)
      delay_hours = normalized_delay_hours(config.settings.to_h["send_delay_hours"])

      if @event == :booking_completed && delivery.notification_type == "post_stay_review_request"
        if delay_hours.zero?
          Notifications::DeliverJob.perform_later(delivery.id)
        else
          scheduled_for = Time.current + delay_hours.hours
          Notifications::DeliverJob.set(wait_until: scheduled_for).perform_later(delivery.id, scheduled_for.iso8601)
        end
      else
        Notifications::DeliverJob.perform_later(delivery.id)
      end
    end

    def normalized_delay_hours(raw_delay)
      value = raw_delay.to_s.strip
      return 2 if value.blank?

      parsed = value.to_i
      parsed.negative? ? 2 : parsed
    end
  end
end
