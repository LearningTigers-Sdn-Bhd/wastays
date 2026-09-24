# frozen_string_literal: true

module Concierge
  module StayAccess
    # Ends the link for one stay. Every device loses access, because a stay
    # session is only valid while its record is live.
    class Revoke
      Result = ApplicationResult.define(:revoked_count)

      def initialize(booking:, now: Time.current)
        @booking = booking
        @now = now
      end

      def call
        return Result.failure("No booking was given.") if booking.blank?

        count = 0
        booking.with_lock do
          booking.concierge_stay_accesses.live.each do |record|
            record.update!(revoked_at: now)
            count += 1
          end
        end

        Rails.logger.info("Concierge stay access revoked booking=#{booking.id} records=#{count}")
        Result.success(revoked_count: count)
      end

      private

      attr_reader :booking, :now
    end
  end
end
