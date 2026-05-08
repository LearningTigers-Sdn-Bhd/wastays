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

      ChannelManagers::SyncJob.perform_now(hotel_id, start_date, end_date)
      Rails.cache.delete(window_key)
    rescue Date::Error
      Rails.cache.delete(window_key)
    end
  end
end
