# frozen_string_literal: true

module ChannelManagers
  class BufferAriSyncJob < ApplicationJob
    queue_as :default

    FLUSH_DELAY = 30.seconds

    RESTRICTION_FIELDS = %w[min_stay max_stay closed_to_arrival closed_to_departure stop_sell].freeze

    def perform(hotel_id, date, type: nil, room_type_id: nil, rate_plan_id: nil)
      hotel = Hotel.find_by(id: hotel_id)
      return if hotel.nil? || !hotel.channel_manager_enabled?

      change = change_for(date.to_date, type.to_s, room_type_id, rate_plan_id)
      return unless AriWindow.new(hotel_id).add(change)

      ChannelManagers::FlushAriSyncJob.set(wait: FLUSH_DELAY).perform_later(hotel_id)
    end

    private

    # One change, shaped like the outbox so it can be merged straight in.
    def change_for(date, type, room_type_id, rate_plan_id)
      day = { "min" => date.to_s, "max" => date.to_s }
      room_type_windows = {}
      rate_plan_windows = {}
      rate_plan_fields = {}

      room_type_windows[room_type_id.to_s] = day if type == "availability" && room_type_id.present?

      if %w[rates restrictions].include?(type) && rate_plan_id.present?
        rate_plan_windows[rate_plan_id.to_s] = day
        # Models and bulk services don't say which fields changed, so assume
        # the ones that kind of change can touch.
        rate_plan_fields[rate_plan_id.to_s] = type == "rates" ? [ "price" ] : RESTRICTION_FIELDS
      end

      {
        "min_date" => date.iso8601,
        "max_date" => date.iso8601,
        "sync_availability" => type == "availability",
        "sync_rates" => type == "rates",
        "sync_restrictions" => type == "restrictions",
        "room_type_windows" => room_type_windows,
        "rate_plan_windows" => rate_plan_windows,
        "rate_plan_fields" => rate_plan_fields
      }
    end
  end
end
