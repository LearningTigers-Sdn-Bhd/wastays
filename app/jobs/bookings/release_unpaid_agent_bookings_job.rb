# frozen_string_literal: true

module Bookings
  # Drives Bookings::ReleaseUnpaidAgentBookings on a schedule. The sweep is
  # idempotent, so a missed run catches up on the next one and an overlapping
  # run releases nothing twice.
  class ReleaseUnpaidAgentBookingsJob < ApplicationJob
    queue_as :default

    def perform
      result = ReleaseUnpaidAgentBookings.call

      return if result.released.empty? && result.failed.empty?

      Rails.logger.info(
        "[#{ReleaseUnpaidAgentBookings::SOURCE}] released #{result.released.size}, " \
        "skipped #{result.skipped.size}, failed #{result.failed.size}"
      )
    end
  end
end
