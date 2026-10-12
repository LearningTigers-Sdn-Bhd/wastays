# frozen_string_literal: true

require "digest"

module ChannelManagers
  # The per-hotel outbox of ARI changes waiting for the next Channex push.
  #
  # Every read-change-write runs under a per-hotel advisory lock. A multi-night
  # booking commits one inventory row per night, and their buffer jobs run side
  # by side; without the lock each reads the same outbox and the last write
  # erases the other nights.
  #
  # The flush claims the outbox (reads and clears it) before pushing, so a
  # change that lands mid-push starts a fresh outbox and its own flush instead
  # of being cleared along with the one already sent.
  class AriWindow
    WINDOW_KEY_PREFIX = "channex:ari:window"
    SCHEDULED_KEY_PREFIX = "channex:ari:scheduled"
    WINDOW_TTL = 20.minutes
    SCHEDULED_TTL = 2.minutes

    def initialize(hotel_id)
      @hotel_id = hotel_id
    end

    # Merges one change into the outbox. Returns true when the caller should
    # schedule a flush, i.e. none is pending yet.
    def add(change)
      with_lock do
        merged = self.class.merge(Rails.cache.read(window_key), change)
        Rails.cache.write(window_key, merged, expires_in: WINDOW_TTL)
        next false if Rails.cache.exist?(scheduled_key)

        Rails.cache.write(scheduled_key, true, expires_in: SCHEDULED_TTL)
        true
      end
    end

    # Takes the outbox for pushing, leaving it empty for whatever comes next.
    def claim
      with_lock do
        window = Rails.cache.read(window_key)
        Rails.cache.delete(window_key)
        Rails.cache.delete(scheduled_key)
        window
      end
    end

    # Puts a claimed outbox back after a push that failed, keeping anything
    # added since it was claimed.
    def restore(window)
      return if window.blank?

      with_lock do
        merged = self.class.merge(Rails.cache.read(window_key), window)
        Rails.cache.write(window_key, merged, expires_in: WINDOW_TTL)
      end
    end

    def self.merge(base, other)
      base ||= {}
      other ||= {}

      {
        "min_date" => [ base["min_date"], other["min_date"] ].compact.min_by(&:to_date),
        "max_date" => [ base["max_date"], other["max_date"] ].compact.max_by(&:to_date),
        "sync_availability" => base.fetch("sync_availability", false) || other.fetch("sync_availability", false),
        "sync_rates" => base.fetch("sync_rates", false) || other.fetch("sync_rates", false),
        "sync_restrictions" => base.fetch("sync_restrictions", false) || other.fetch("sync_restrictions", false),
        "room_type_windows" => merge_ranges(base["room_type_windows"], other["room_type_windows"]),
        "rate_plan_windows" => merge_ranges(base["rate_plan_windows"], other["rate_plan_windows"]),
        "rate_plan_fields" => (base["rate_plan_fields"] || {}).merge(other["rate_plan_fields"] || {}) { |_, a, b| (a + b).uniq }
      }
    end

    def self.merge_ranges(base, other)
      (base || {}).merge(other || {}) do |_, a, b|
        {
          "min" => [ a["min"], b["min"] ].min_by(&:to_date),
          "max" => [ a["max"], b["max"] ].max_by(&:to_date)
        }
      end
    end
    private_class_method :merge_ranges

    private

    def window_key
      "#{WINDOW_KEY_PREFIX}:#{@hotel_id}"
    end

    def scheduled_key
      "#{SCHEDULED_KEY_PREFIX}:#{@hotel_id}"
    end

    def with_lock
      ActiveRecord::Base.transaction do
        lock_id = Digest::SHA256.digest(window_key)[0, 8].unpack1("q>")
        ActiveRecord::Base.connection.exec_query(
          "SELECT 1 AS acquired FROM pg_advisory_xact_lock($1)",
          "advisory_lock",
          [ lock_id ]
        )
        yield
      end
    end
  end
end
