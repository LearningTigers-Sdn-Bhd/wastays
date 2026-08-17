# frozen_string_literal: true

module Notifications
  class Dispatcher
    EVENT_TO_NOTIFICATION_TYPE = {
      booking_confirmed: %w[pre_arrival_notification in_stay_guest_messaging],
      booking_checked_in: "check_in_confirmation",
      booking_completed: %w[post_stay_review_request check_out_receipt_message],
      booking_updated: %w[pre_arrival_notification in_stay_guest_messaging],
      booking_cancelled: []
    }.freeze

    NOTIFICATION_FEATURE = {
      "pre_arrival_notification" => "automated_prearrival",
      "check_in_confirmation" => "checkin_confirmation",
      "in_stay_guest_messaging" => "welcoming_instay_messaging",
      "check_out_receipt_message" => "checkout_receipt_review",
      "post_stay_review_request" => "checkout_receipt_review"
    }.freeze

    def initialize(event:, booking:)
      @event = event.to_sym
      @booking = booking
    end

    def call
      # 1. Handle Cancellation: Delete all pending/failed notification deliveries
      if @event == :booking_cancelled
        @booking.notification_deliveries.where(status: [ "pending", "failed" ]).destroy_all
        return []
      end

      return [] if @booking.hotel.training_mode?

      notification_types = Array(EVENT_TO_NOTIFICATION_TYPE.fetch(@event))
      notification_types = notification_types.select { |type| feature_enabled_for_type?(type) }
      return dispatch_scheduled_notifications(notification_types) if scheduled_only_events?

      notification_types.flat_map do |notification_type|
        config = NotificationConfig.find_by(hotel: @booking.hotel, notification_type: notification_type)
        next [] unless config&.enabled?

        payload, payload_error = payload_with_error(notification_type, config)
        Array(config.channels).map do |channel|
          next if unreachable_channel?(channel)

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

    def feature_enabled_for_type?(notification_type)
      slug = NOTIFICATION_FEATURE[notification_type]
      return true if slug.nil?

      @booking.hotel.feature_enabled?(slug)
    end

    def dispatch_pre_arrival(event)
      scheduler = Notifications::PreArrivalScheduler.new(booking: @booking)
      return scheduler.reschedule_pending!(trigger_event: event.to_s) if event == :booking_updated

      scheduler.schedule!(trigger_event: event.to_s)
    end

    def dispatch_in_stay(event)
      scheduler = Notifications::InStayScheduler.new(booking: @booking)
      return scheduler.reschedule_pending!(trigger_event: event.to_s) if event == :booking_updated

      scheduler.schedule!(trigger_event: event.to_s)
    end

    def dispatch_scheduled_notifications(notification_types)
      deliveries = []
      deliveries.concat(Array(dispatch_pre_arrival(@event))) if notification_types.include?("pre_arrival_notification")
      deliveries.concat(Array(dispatch_in_stay(@event))) if notification_types.include?("in_stay_guest_messaging")
      deliveries
    end

    def scheduled_only_events?
      @event.in?([ :booking_confirmed, :booking_updated ])
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
      when "in_stay_guest_messaging"
        raise ArgumentError, "In-stay messaging is handled by scheduler"
      else
        raise ArgumentError, "Unsupported notification type: #{notification_type}"
      end
    end

    # A desk booking may carry only a phone number. Queuing an email for it
    # would just fail on send, so the channel is skipped rather than recorded
    # as a delivery that was never deliverable.
    def unreachable_channel?(channel)
      channel.to_s == "email" && @booking.guest_email.blank?
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
