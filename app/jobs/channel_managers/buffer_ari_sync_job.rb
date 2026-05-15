# frozen_string_literal: true

module ChannelManagers
  class BufferAriSyncJob < ApplicationJob
    queue_as :default

    WINDOW_KEY_PREFIX = "channex:ari:window".freeze
    SCHEDULED_KEY_PREFIX = "channex:ari:scheduled".freeze
    FLUSH_DELAY = 30.seconds

    def perform(hotel_id, date, type: nil, room_type_id: nil, rate_plan_id: nil)
      hotel = Hotel.find_by(id: hotel_id)
      return if hotel.nil? || hotel.preferred_channel_manager.blank?

      changed_date = date.to_date
      window_key = "#{WINDOW_KEY_PREFIX}:#{hotel_id}"
      scheduled_key = "#{SCHEDULED_KEY_PREFIX}:#{hotel_id}"

      existing = Rails.cache.read(window_key) || {}
      min_date = [ existing["min_date"], changed_date ].compact.map(&:to_date).min
      max_date = [ existing["max_date"], changed_date ].compact.map(&:to_date).max

      # Track what needs syncing
      sync_availability = existing.fetch("sync_availability", false) || type.to_s == "availability"
      sync_rates = existing.fetch("sync_rates", false) || type.to_s == "rates"
      sync_restrictions = existing.fetch("sync_restrictions", false) || type.to_s == "restrictions"

      # Collect specific windows for surgical updates
      room_type_windows = (existing["room_type_windows"] || {})
      if type.to_s == "availability" && room_type_id.present?
        win = room_type_windows[room_type_id.to_s] || { "min" => changed_date.to_s, "max" => changed_date.to_s }
        win["min"] = [ win["min"].to_date, changed_date ].min.to_s
        win["max"] = [ win["max"].to_date, changed_date ].max.to_s
        room_type_windows[room_type_id.to_s] = win
      end

      rate_plan_windows = (existing["rate_plan_windows"] || {})
      rate_plan_fields = (existing["rate_plan_fields"] || {})

      if (type.to_s == "restrictions" || type.to_s == "rates") && rate_plan_id.present?
        win = rate_plan_windows[rate_plan_id.to_s] || { "min" => changed_date.to_s, "max" => changed_date.to_s }
        win["min"] = [ win["min"].to_date, changed_date ].min.to_s
        win["max"] = [ win["max"].to_date, changed_date ].max.to_s
        rate_plan_windows[rate_plan_id.to_s] = win
        
        # Track specific fields modified for this rate plan
        fields = (rate_plan_fields[rate_plan_id.to_s] || [])
        # When called from models/bulk services, we might not have specific fields, 
        # so we assume common ones based on type.
        new_fields = if type.to_s == "rates"
          ["price"]
        elsif type.to_s == "restrictions"
          ["min_stay", "max_stay", "closed_to_arrival", "closed_to_departure", "stop_sell"]
        else
          []
        end
        rate_plan_fields[rate_plan_id.to_s] = (fields + new_fields).uniq
      end

      Rails.cache.write(
        window_key,
        {
          "min_date" => min_date.iso8601,
          "max_date" => max_date.iso8601,
          "sync_availability" => sync_availability,
          "sync_rates" => sync_rates,
          "sync_restrictions" => sync_restrictions,
          "room_type_windows" => room_type_windows,
          "rate_plan_windows" => rate_plan_windows,
          "rate_plan_fields" => rate_plan_fields
        },
        expires_in: 20.minutes
      )

      return if Rails.cache.exist?(scheduled_key)

      Rails.cache.write(scheduled_key, true, expires_in: 2.minutes)
      ChannelManagers::FlushAriSyncJob.set(wait: FLUSH_DELAY).perform_later(hotel_id)
    end
  end
end
