# frozen_string_literal: true

module Concierge
  module StayAccess
    # Gives one booking its live stay-access record. A second call returns the
    # same record, so check-in can call this again without a new link.
    class Ensure
      Result = ApplicationResult.define(:stay_access, :created)

      def initialize(booking:, now: Time.current)
        @booking = booking
        @now = now
      end

      def call
        eligibility = Eligibility.new(booking: booking, now: now).call
        return Result.failure(eligibility.error) unless eligibility.success?

        booking.with_lock do
          existing = booking.concierge_stay_accesses.live.first
          return Result.success(stay_access: existing, created: false) if existing

          Result.success(stay_access: create_record, created: true)
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        Rails.logger.warn("Concierge stay access not created booking=#{booking&.id} error=#{e.class}")
        Result.failure("This stay page is not available.")
      end

      private

      attr_reader :booking, :now

      def create_record
        booking.concierge_stay_accesses.create!(hotel: booking.hotel)
      end
    end
  end
end
