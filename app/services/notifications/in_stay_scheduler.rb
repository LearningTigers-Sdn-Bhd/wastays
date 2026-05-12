# frozen_string_literal: true

module Notifications
  class InStayScheduler
    NOTIFICATION_TYPE = "in_stay_guest_messaging"
    DEFAULT_CHANNELS = %w[whatsapp email].freeze
    DEFAULT_RULES = {
      "mid_stay" => { "enabled" => true, "time" => "12:00" },
      "upsell" => { "enabled" => true, "time" => "17:00" },
      "activity" => { "enabled" => true, "time" => "10:00" }
    }.freeze
    DEFAULT_QUIET_HOURS = { "enabled" => true, "start" => "22:00", "end" => "08:00" }.freeze

    def initialize(booking:)
      @booking = booking
    end

    def schedule!(trigger_event: "booking_confirmed")
      config = config_for_booking
      return [] unless config&.enabled?

      channels(config).flat_map do |channel|
        enabled_rules(config).map do |rule_key, rule_settings|
          upsert_rule_delivery(
            channel: channel,
            rule_key: rule_key,
            rule_settings: rule_settings,
            trigger_event: trigger_event
          )
        end
      end.compact
    end

    def reschedule_pending!(trigger_event: "booking_updated")
      config = config_for_booking
      return [] unless config&.enabled?

      pending_deliveries = NotificationDelivery.where(
        hotel: @booking.hotel,
        booking: @booking,
        notification_type: NOTIFICATION_TYPE,
        status: "pending"
      )

      pending_deliveries.find_each do |delivery|
        rule_key = delivery.payload.to_h["rule_key"].to_s
        next unless enabled_rules(config).key?(rule_key)

        schedule_rule_delivery!(
          delivery: delivery,
          rule_key: rule_key,
          rule_settings: enabled_rules(config).fetch(rule_key),
          trigger_event: trigger_event
        )
      end
    end

    private

    def config_for_booking
      NotificationConfig.find_by(hotel: @booking.hotel, notification_type: NOTIFICATION_TYPE)
    end

    def channels(config)
      configured = Array(config.channels).map(&:to_s).presence
      configured || DEFAULT_CHANNELS
    end

    def enabled_rules(config)
      merged_rules = DEFAULT_RULES.deep_merge(config.settings.to_h.fetch("rules", {}).to_h)
      merged_rules.select { |_key, value| ActiveModel::Type::Boolean.new.cast(value.to_h["enabled"]) }
    end

    def quiet_hours(config)
      DEFAULT_QUIET_HOURS.merge(config.settings.to_h.fetch("quiet_hours", {}).to_h)
    end

    def upsert_rule_delivery(channel:, rule_key:, rule_settings:, trigger_event:)
      key = [ @booking.hotel_id, @booking.id, NOTIFICATION_TYPE, channel, rule_key ].join(":")
      delivery = NotificationDelivery.find_or_initialize_by(idempotency_key: key)

      if delivery.persisted?
        return delivery unless delivery.status == "pending"

        schedule_rule_delivery!(
          delivery: delivery,
          rule_key: rule_key,
          rule_settings: rule_settings,
          trigger_event: trigger_event
        )
        return delivery
      end

      scheduled_for = next_valid_schedule_time(rule_key: rule_key, time_hhmm: rule_settings.to_h["time"], quiet: quiet_hours(config_for_booking))
      payload = payload(rule_key: rule_key, scheduled_for: scheduled_for || Time.current)
      status = scheduled_for.present? ? "pending" : "skipped"

      delivery.assign_attributes(
        hotel: @booking.hotel,
        booking: @booking,
        notification_type: NOTIFICATION_TYPE,
        channel: channel,
        trigger_event: trigger_event,
        status: status,
        payload: payload,
        failed_at: nil,
        error_message: (no_future_slot_error(rule_key) if status == "skipped")
      )
      delivery.save!
      enqueue_delivery(delivery, scheduled_for) if status == "pending"
      delivery
    end

    def schedule_rule_delivery!(delivery:, rule_key:, rule_settings:, trigger_event:)
      scheduled_for = next_valid_schedule_time(rule_key: rule_key, time_hhmm: rule_settings.to_h["time"], quiet: quiet_hours(config_for_booking))
      payload = payload(rule_key: rule_key, scheduled_for: scheduled_for || Time.current)

      if scheduled_for.blank?
        delivery.update!(
          trigger_event: trigger_event,
          status: "skipped",
          failed_at: nil,
          error_message: no_future_slot_error(rule_key),
          payload: payload
        )
        return
      end

      delivery.update!(
        trigger_event: trigger_event,
        status: "pending",
        failed_at: nil,
        error_message: nil,
        payload: payload
      )
      enqueue_delivery(delivery, scheduled_for)
    end

    def payload(rule_key:, scheduled_for:)
      Notifications::PayloadBuilders::InStayGuestMessaging.new(
        booking: @booking,
        rule_key: rule_key,
        scheduled_for: scheduled_for
      ).call
    end

    def enqueue_delivery(delivery, scheduled_for)
      Notifications::DeliverJob.set(wait_until: scheduled_for).perform_later(delivery.id, scheduled_for.iso8601)
    end

    def normalized_schedule_time(rule_key:, time_hhmm:, quiet:)
      base_date = case rule_key
      when "mid_stay"
        mid_stay_date
      when "upsell"
        @booking.check_in.to_date
      when "activity"
        @booking.check_out.to_date - 1.day
      end

      hh, mm = normalized_time(time_hhmm)
      scheduled_for = Time.zone.local(base_date.year, base_date.month, base_date.day, hh, mm, 0)
      quiet_hours_adjusted_time(scheduled_for, quiet)
    end

    def next_valid_schedule_time(rule_key:, time_hhmm:, quiet:)
      scheduled_for = normalized_schedule_time(rule_key: rule_key, time_hhmm: time_hhmm, quiet: quiet)

      while scheduled_for <= Time.current
        scheduled_for = quiet_hours_adjusted_time(scheduled_for + 1.day, quiet)
      end

      return nil if scheduled_for.to_date >= @booking.check_out.to_date

      scheduled_for
    end

    def mid_stay_date
      nights = [ (@booking.check_out.to_date - @booking.check_in.to_date).to_i, 1 ].max
      offset = [ (nights / 2), 0 ].max
      @booking.check_in.to_date + offset.days
    end

    def normalized_time(raw_time)
      value = raw_time.to_s.strip
      return [ 12, 0 ] unless /\A([01]\d|2[0-3]):[0-5]\d\z/.match?(value)

      hours, mins = value.split(":").map(&:to_i)
      [ hours, mins ]
    end

    def quiet_hours_adjusted_time(scheduled_for, quiet)
      return scheduled_for unless ActiveModel::Type::Boolean.new.cast(quiet["enabled"])

      start_h, start_m = normalized_time(quiet["start"])
      end_h, end_m = normalized_time(quiet["end"])
      minute_of_day = scheduled_for.hour * 60 + scheduled_for.min
      start_minute = start_h * 60 + start_m
      end_minute = end_h * 60 + end_m

      in_quiet = if start_minute < end_minute
        minute_of_day >= start_minute && minute_of_day < end_minute
      else
        minute_of_day >= start_minute || minute_of_day < end_minute
      end

      return scheduled_for unless in_quiet

      if start_minute < end_minute
        Time.zone.local(scheduled_for.year, scheduled_for.month, scheduled_for.day, end_h, end_m, 0)
      elsif minute_of_day >= start_minute
        next_day = scheduled_for + 1.day
        Time.zone.local(next_day.year, next_day.month, next_day.day, end_h, end_m, 0)
      else
        Time.zone.local(scheduled_for.year, scheduled_for.month, scheduled_for.day, end_h, end_m, 0)
      end
    end

    def no_future_slot_error(rule_key)
      "In-stay #{rule_key} has no future schedule before check-out"
    end
  end
end
