# frozen_string_literal: true

module Concierge
  module StayAccess
    # Tests the confirmation code that an unknown device sends.
    #
    # Every failure gives the same message, so the answer never says whether the
    # stay, the guest, or the code exists. The attempt count and the lock live on
    # the stay-access record, so a guest cannot get a new budget from a new
    # browser. The raw code never enters a log.
    class VerifyDevice
      GENERIC_ERROR = "That code did not match. Please try again."
      LOCKED_ERROR = "This stay page is locked. Please ask for a new email link."
      SLOW_DOWN_ERROR = "Please wait a moment, then try again."

      # The gap doubles after each wrong code: 2, 4, 8, then 16 seconds.
      BASE_DELAY = 2.seconds
      MAX_DELAY = 16.seconds

      Result = ApplicationResult.define(:stay_access, :booking, :retry_after, :locked)

      def initialize(stay_access:, confirmation_code:, request_ip: nil, now: Time.current)
        @stay_access = stay_access
        @confirmation_code = confirmation_code
        @request_ip = request_ip
        @now = now
      end

      def call
        return Result.failure(GENERIC_ERROR) unless stay_access_usable?

        stay_access.with_lock do
          return locked_result if stay_access.locked?(now: now)

          reset_stale_window
          wait = delay_left
          return Result.failure(SLOW_DOWN_ERROR, retry_after: wait) if wait.positive?

          code_matches? ? accept : reject
        end
      end

      private

      attr_reader :stay_access, :confirmation_code, :request_ip, :now

      def stay_access_usable?
        return false if stay_access.blank? || stay_access.revoked?

        Eligibility.new(booking: stay_access.booking, now: now).call.success?
      end

      def code_matches?
        given = confirmation_code.to_s.strip.upcase
        return false if given.blank?

        ActiveSupport::SecurityUtils.secure_compare(expected_code, given)
      end

      def expected_code
        stay_access.booking.confirmation_token.to_s.strip.upcase
      end

      # A window older than one hour starts again, so a guest who returns the
      # next day gets the full budget.
      def reset_stale_window
        return if stay_access.attempt_window_open?(now: now)

        stay_access.update!(attempt_count: 0, attempt_window_started_at: nil, last_attempt_at: nil)
      end

      def delay_left
        return 0 if stay_access.attempt_count.zero? || stay_access.last_attempt_at.blank?

        required = [ BASE_DELAY * (2**(stay_access.attempt_count - 1)), MAX_DELAY ].min
        passed = now - stay_access.last_attempt_at
        [ (required - passed).ceil, 0 ].max
      end

      def accept
        stay_access.update!(
          attempt_count: 0,
          attempt_window_started_at: nil,
          last_attempt_at: nil,
          locked_until: nil
        )

        Result.success(stay_access: stay_access, booking: stay_access.booking)
      end

      def reject
        count = stay_access.attempt_count + 1
        lock = count >= ConciergeStayAccess::MAX_ATTEMPTS

        stay_access.update!(
          attempt_count: count,
          attempt_window_started_at: stay_access.attempt_window_started_at || now,
          last_attempt_at: now,
          locked_until: lock ? now + ConciergeStayAccess::LOCK_DURATION : nil
        )

        log_failure(count, lock)
        lock ? locked_result : Result.failure(GENERIC_ERROR)
      end

      def locked_result
        Result.failure(LOCKED_ERROR, locked: true, retry_after: seconds_until_unlock)
      end

      def seconds_until_unlock
        return 0 if stay_access.locked_until.blank?

        [ (stay_access.locked_until - now).ceil, 0 ].max
      end

      def log_failure(count, lock)
        Rails.logger.info(
          "Concierge stay verification failed " \
          "stay_access=#{stay_access.id} hotel=#{stay_access.hotel_id} " \
          "attempt=#{count} locked=#{lock} ip=#{request_ip}"
        )
      end
    end
  end
end
