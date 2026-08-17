# frozen_string_literal: true

module Notifications
  class PreArrivalScheduler
    NOTIFICATION_TYPE = "pre_arrival_notification"
    DEFAULT_CHANNELS = %w[whatsapp email].freeze
    STAGE_DAY_OFFSETS = {
      "d2" => 2,
      "d1" => 1
    }.freeze

    def initialize(booking:)
      @booking = booking
    end

    def schedule!(trigger_event: "booking_confirmed")
      config = config_for_booking
      return [] unless config&.enabled?

      deliveries = []
      channels(config).each do |channel|
        stages(config).each do |stage|
          scheduled_for = schedule_time_for(stage)
          deliveries << upsert_stage_delivery(
            channel: channel,
            stage: stage,
            scheduled_for: scheduled_for,
            trigger_event: trigger_event
          )
        end
      end

      deliveries.compact
    end

    def reschedule_pending!(trigger_event: "booking_updated")
      pending_deliveries = NotificationDelivery.where(
        hotel: @booking.hotel,
        booking: @booking,
        notification_type: NOTIFICATION_TYPE,
        status: "pending"
      )

      pending_deliveries.find_each do |delivery|
        stage = delivery.payload.to_h["stage"] || delivery.payload.to_h[:stage]
        next unless STAGE_DAY_OFFSETS.key?(stage)

        scheduled_for = schedule_time_for(stage)
        if scheduled_for <= Time.current
          delivery.update!(
            status: "failed",
            failed_at: Time.current,
            error_message: "Pre-arrival #{stage} schedule is in the past",
            trigger_event: trigger_event,
            payload: delivery.payload.to_h.merge("scheduled_for" => scheduled_for.iso8601)
          )
          next
        end

        delivery.update!(
          trigger_event: trigger_event,
          payload: delivery.payload.to_h.merge("scheduled_for" => scheduled_for.iso8601)
        )
        Notifications::DeliverJob.set(wait_until: scheduled_for).perform_later(delivery.id, scheduled_for.iso8601)
      end
    end

    private

    def config_for_booking
      NotificationConfig.find_by(hotel: @booking.hotel, notification_type: NOTIFICATION_TYPE)
    end

    def channels(config)
      configured = Array(config.channels).map(&:to_s).presence
      channels = configured || DEFAULT_CHANNELS
      # A desk booking may carry only a phone number; scheduling mail against it
      # would just fail when the stage comes due.
      return channels if @booking.guest_email.present?

      channels - [ "email" ]
    end

    def stages(config)
      configured = Array(config.settings.to_h["stages"]).map(&:to_s)
      selected = configured & STAGE_DAY_OFFSETS.keys
      selected.presence || STAGE_DAY_OFFSETS.keys
    end

    def schedule_time_for(stage)
      (@booking.check_in.to_time.in_time_zone.beginning_of_day - STAGE_DAY_OFFSETS.fetch(stage).days)
    end

    def upsert_stage_delivery(channel:, stage:, scheduled_for:, trigger_event:)
      key = [ @booking.hotel_id, @booking.id, NOTIFICATION_TYPE, channel, stage ].join(":")
      delivery = NotificationDelivery.find_or_initialize_by(idempotency_key: key)
      return if delivery.persisted?

      payload = Notifications::PayloadBuilders::PreArrivalNotification.new(
        booking: @booking,
        stage: stage,
        scheduled_for: scheduled_for
      ).call

      status = scheduled_for <= Time.current ? "failed" : "pending"
      error_message = ("Pre-arrival #{stage} schedule is in the past" if status == "failed")

      delivery.assign_attributes(
        hotel: @booking.hotel,
        booking: @booking,
        notification_type: NOTIFICATION_TYPE,
        channel: channel,
        trigger_event: trigger_event,
        status: status,
        payload: payload,
        failed_at: (Time.current if status == "failed"),
        error_message: error_message
      )
      delivery.save!

      if status == "pending"
        Notifications::DeliverJob.set(wait_until: scheduled_for).perform_later(delivery.id, scheduled_for.iso8601)
      end

      delivery
    end
  end
end
