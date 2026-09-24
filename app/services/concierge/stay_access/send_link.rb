# frozen_string_literal: true

module Concierge
  module StayAccess
    # Mails the stay link to the booking email.
    #
    # Check-in calls this one time. The locked page calls it again when a guest
    # runs out of attempts. The send cap stops a stranger who holds the URL from
    # mailing the guest without end.
    class SendLink
      NO_EMAIL = "This booking has no email address."
      COOLDOWN = "A link went out already. Please wait, then ask again."

      Result = ApplicationResult.define(:stay_access, :masked_email, :retry_after)

      def initialize(booking:, reason: :check_in, now: Time.current)
        @booking = booking
        @reason = reason.to_s
        @now = now
      end

      def call
        ensured = Ensure.new(booking: booking, now: now).call
        return Result.failure(ensured.error) unless ensured.success?
        return Result.failure(NO_EMAIL) if email.blank?

        stay_access = ensured.stay_access

        stay_access.with_lock do
          reset_stale_window(stay_access)
          return cooldown(stay_access) if stay_access.sends_left(now: now).zero?

          deliver(stay_access)
          record_send(stay_access)
        end

        Rails.logger.info(
          "Concierge stay link sent stay_access=#{stay_access.id} " \
          "hotel=#{stay_access.hotel_id} reason=#{reason}"
        )

        Result.success(stay_access: stay_access, masked_email: masked_email)
      end

      private

      attr_reader :booking, :reason, :now

      def email
        @email ||= (booking.guest_email.presence || booking.primary_guest&.email)
          .to_s.strip.downcase.presence
      end

      # A window older than one hour starts again, so a guest who returns the
      # next day can ask for the link.
      def reset_stale_window(stay_access)
        return if stay_access.send_window_open?(now: now)

        stay_access.update!(send_count: 0, send_window_started_at: nil)
      end

      def deliver(stay_access)
        GuestMailer.stay_link(stay_access, email).deliver_later
      end

      def record_send(stay_access)
        stay_access.update!(
          send_count: stay_access.send_count + 1,
          send_window_started_at: stay_access.send_window_started_at || now,
          link_sent_at: now
        )
      end

      def cooldown(stay_access)
        retry_after = (stay_access.send_window_started_at + ConciergeStayAccess::SEND_WINDOW - now).ceil
        Result.failure(COOLDOWN, stay_access: stay_access, retry_after: [ retry_after, 0 ].max)
      end

      def masked_email
        local, domain = email.to_s.split("@", 2)
        return if local.blank? || domain.blank?

        "#{local.first}#{'•' * [ local.length - 1, 3 ].min}@#{domain}"
      end
    end
  end
end
