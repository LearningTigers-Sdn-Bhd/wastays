# frozen_string_literal: true

module ChannelManagers
  class FlushAriSyncJob < ApplicationJob
    queue_as :default

    retry_on Channex::Client::RetryableRequestError, wait: :exponentially_longer, attempts: 8

    WINDOW_KEY_PREFIX = "channex:ari:window".freeze
    SCHEDULED_KEY_PREFIX = "channex:ari:scheduled".freeze

    def perform(hotel_id)
      hotel = Hotel.find_by(id: hotel_id)
      return if hotel.nil? || hotel.preferred_channel_manager.blank?

      window_key = "#{WINDOW_KEY_PREFIX}:#{hotel_id}"
      scheduled_key = "#{SCHEDULED_KEY_PREFIX}:#{hotel_id}"
      window = Rails.cache.read(window_key)

      Rails.cache.delete(scheduled_key)
      return if window.blank?

      start_date = Date.parse(window["min_date"])
      end_date = Date.parse(window["max_date"])
      sync_availability = window.fetch("sync_availability", true)
      sync_rates = window.fetch("sync_rates", true)
      sync_restrictions = window.fetch("sync_restrictions", true)
      room_type_ids = window["room_type_windows"]
      rate_plan_ids = window["rate_plan_windows"]
      rate_plan_fields = window["rate_plan_fields"]

      ChannelManagers::SyncJob.perform_now(
        hotel_id,
        start_date,
        end_date,
        sync_availability: sync_availability,
        sync_rates: sync_rates,
        sync_restrictions: sync_restrictions,
        room_type_ids: room_type_ids,
        rate_plan_ids: rate_plan_ids,
        rate_plan_fields: rate_plan_fields
      )
      Rails.cache.delete(window_key)
    rescue Date::Error
      Rails.cache.delete(window_key)
    end
  end
end
