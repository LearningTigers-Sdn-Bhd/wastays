# frozen_string_literal: true

module Channex
  # Channex allows each property 10 availability and 10 restriction/price
  # calls a minute, and fails certification for a PMS without a limiter.
  #
  # Budgets are counted per clock minute. Any 60 seconds spans at most two of
  # those minutes, so a budget of 5 keeps every rolling minute within 10 even
  # when calls bunch up either side of a minute boundary.
  class AriRateLimiter
    LIMITED_PATHS = %w[/availability /restrictions].freeze
    CALLS_PER_MINUTE = 5

    # True when the call may go ahead; calls outside the ARI endpoints are
    # never limited.
    def self.allow?(path, body)
      return true unless LIMITED_PATHS.include?(path)

      property_id = property_id_in(body)
      return true if property_id.blank?

      Rails.cache.increment(budget_key(property_id, path), 1, expires_in: 2.minutes).to_i <= CALLS_PER_MINUTE
    end

    # True when every one of paths still has budget this minute. Spends
    # nothing: a push checks before sending anything, so a call throttled
    # half-way through doesn't make the retry re-send (and re-spend) the
    # calls that already went out.
    def self.room_for?(property_id, paths)
      paths.all? { |path| Rails.cache.read(budget_key(property_id, path)).to_i < CALLS_PER_MINUTE }
    end

    def self.budget_key(property_id, path)
      "channex:ari_rate:#{property_id}:#{path}:#{Time.current.to_i / 60}"
    end
    private_class_method :budget_key

    def self.property_id_in(body)
      value = Array(body.is_a?(Hash) ? (body[:values] || body["values"]) : nil).first
      value.is_a?(Hash) ? (value[:property_id] || value["property_id"]) : nil
    end
    private_class_method :property_id_in
  end
end
