# frozen_string_literal: true

module Notifications
  class Dispatcher
    EVENT_TO_NOTIFICATION_TYPE = {
      booking_checked_in: "check_in_confirmation"
    }.freeze

    def initialize(event:, booking:)
      @event = event.to_sym
      @booking = booking
    end

    def call
      notification_type = EVENT_TO_NOTIFICATION_TYPE.fetch(@event)
      config = NotificationConfig.find_by(hotel: @booking.hotel, notification_type: notification_type)
      return [] unless config&.enabled?

      payload = payload_for(notification_type)

      Array(config.channels).map do |channel|
        create_delivery(notification_type:, channel: channel.to_s, payload:)
      end.compact
    end

    private

    def payload_for(notification_type)
      case notification_type
      when "check_in_confirmation"
        Notifications::PayloadBuilders::CheckInConfirmation.new(booking: @booking).call
      else
        raise ArgumentError, "Unsupported notification type: #{notification_type}"
      end
    end

    def create_delivery(notification_type:, channel:, payload:)
      key = [ @booking.hotel_id, @booking.id, notification_type, channel, @event ].join(":")
      delivery = NotificationDelivery.find_or_initialize_by(idempotency_key: key)
      return if delivery.persisted?

      delivery.assign_attributes(
        hotel: @booking.hotel,
        booking: @booking,
        notification_type: notification_type,
        channel: channel,
        trigger_event: @event.to_s,
        status: "pending",
        payload: payload
      )
      delivery.save!
      Notifications::DeliverJob.perform_later(delivery.id)
      delivery
    end
  end
end
