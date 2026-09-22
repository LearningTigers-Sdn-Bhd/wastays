# frozen_string_literal: true

module Concierge
  module StayAccess
    # Decides whether one booking can hold a stay page, and until when.
    #
    # An in-house booking gets full access. A booking that checked out keeps
    # access for the grace period, so the guest can still read the folio, the
    # invoice, and send a refund request.
    class Eligibility
      GRACE_PERIOD = 7.days
      UNAVAILABLE = "This stay page is not available."

      Result = ApplicationResult.define(:level, :expires_at)

      def initialize(booking:, now: Time.current)
        @booking = booking
        @now = now
      end

      def call
        return Result.failure(UNAVAILABLE) if booking.blank?
        return Result.success(level: :full, expires_at: expires_at) if in_house?
        return Result.success(level: :grace, expires_at: expires_at) if inside_grace?

        Result.failure(UNAVAILABLE)
      end

      private

      attr_reader :booking, :now

      def in_house?
        booking.status.in?(Booking::IN_HOUSE_STATUSES)
      end

      def inside_grace?
        booking.status == "completed" && expires_at > now
      end

      # An old record can have no check-out time. The planned departure is the
      # same fallback that Booking#payment_concluded_at uses.
      def expires_at
        @expires_at ||= (booking.checked_out_at || booking.check_out) + GRACE_PERIOD
      end
    end
  end
end
