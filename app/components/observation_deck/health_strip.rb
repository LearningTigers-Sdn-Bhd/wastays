# frozen_string_literal: true

module ObservationDeck
  class HealthStrip < ViewComponent::Base
    def initialize(scope_label:, total_requests:, error_count:, error_rate:, average_latency:, unacknowledged_errors:, error_path:)
      @scope_label = scope_label
      @total_requests = total_requests
      @error_count = error_count
      @error_rate = error_rate
      @average_latency = average_latency
      @unacknowledged_errors = unacknowledged_errors
      @error_path = error_path
    end
  end
end
