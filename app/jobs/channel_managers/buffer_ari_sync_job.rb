# frozen_string_literal: true

module ChannelManagers
  class BufferAriSyncJob < ApplicationJob
    queue_as :default

    WINDOW_KEY_PREFIX = "channex:ari:window".freeze
    SCHEDULED_KEY_PREFIX = "channex:ari:scheduled".freeze
    FLUSH_DELAY = 30.seconds

    def perform(hotel_id, date)
      hotel = Hotel.find_by(id: hotel_id)
      return if hotel.nil? || hotel.preferred_channel_manager.blank?

      changed_date = date.to_date
      window_key = "#{WINDOW_KEY_PREFIX}:#{hotel_id}"
      scheduled_key = "#{SCHEDULED_KEY_PREFIX}:#{hotel_id}"

      existing = Rails.cache.read(window_key) || {}
      min_date = [ existing["min_date"], changed_date ].compact.map(&:to_date).min
      max_date = [ existing["max_date"], changed_date ].compact.map(&:to_date).max

      Rails.cache.write(
        window_key,
        { "min_date" => min_date.iso8601, "max_date" => max_date.iso8601 },
        expires_in: 20.minutes
      )

      return if Rails.cache.exist?(scheduled_key)

      Rails.cache.write(scheduled_key, true, expires_in: 2.minutes)
      ChannelManagers::FlushAriSyncJob.set(wait: FLUSH_DELAY).perform_later(hotel_id)
    end
  end
end
