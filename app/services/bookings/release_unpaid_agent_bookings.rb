# frozen_string_literal: true

module Bookings
  # Cancels agent bookings whose payment deadline has passed without payment,
  # returning the rooms to sale.
  #
  # This is an automated cancellation in a money path, so two things matter more
  # than the sweep itself:
  #
  # * **Every release is logged.** Cancellation goes through
  #   Bookings::TransitionStatus, which writes a BookingAuditLog naming this
  #   service as the source and the deadline as the reason. A release nobody can
  #   audit is not acceptable.
  # * **It is idempotent.** It only ever selects bookings that are still
  #   confirmed and still unpaid, each is re-checked under a lock, and a booking
  #   already cancelled is skipped rather than cancelled twice. Running it twice
  #   in the same minute changes nothing the first run did not.
  #
  # A booking is spared when the agent has done their part: payment recorded, or
  # a remittance slip uploaded and still awaiting review. The clock stops on
  # upload, not on approval -- an agent should not lose rooms to the hotel's
  # review queue -- and resumes only if the submission is rejected.
  class ReleaseUnpaidAgentBookings
    SOURCE = "payment_deadline_sweeper"
    RELEASABLE_STATUSES = %w[confirmed].freeze
    UNPAID_PAYMENT_STATUSES = %w[pending failed].freeze

    Result = Struct.new(:released, :skipped, :failed, keyword_init: true) do
      def released_count = released.size
    end

    def self.call(...) = new(...).call

    def initialize(hotel: nil, now: Time.current)
      @hotel = hotel
      @now = now
    end

    def call
      result = Result.new(released: [], skipped: [], failed: [])

      due_bookings.find_each do |booking|
        outcome = release(booking)
        result[outcome.fetch(:status)] << outcome.fetch(:booking_id)
      end

      result
    end

    private

    # Wall-clock, deliberately: see Bookings::PaymentHold.
    def due_bookings
      scope = Booking
        .where.not(payment_due_at: nil)
        .where(payment_due_at: ..@now)
        .where(status: RELEASABLE_STATUSES)
        .where(payment_status: UNPAID_PAYMENT_STATUSES)
        .where.not(hotel_corporate_account_id: nil)
      scope = scope.where(hotel: @hotel) if @hotel
      scope.order(:payment_due_at)
    end

    def release(booking)
      booking.with_lock do
        booking.reload

        # Re-checked under the lock: the agent may have paid, or another worker
        # may have released this booking, since the scope was read.
        return skip(booking) unless releasable?(booking)

        result = ::Bookings::TransitionStatus.new(
          booking: booking,
          status: "cancelled",
          user: nil,
          options: { source: SOURCE, reason: reason_for(booking) }
        ).call

        return failure(booking, result) unless result.success?

        { status: :released, booking_id: booking.id }
      end
    # A night audit in progress makes TransitionStatus refuse the change. That is
    # the right answer -- the sweep must not edit a hotel's books mid-audit -- so
    # the booking is recorded as failed and picked up on the next run rather than
    # forced through.
    rescue StandardError => e
      Rails.logger.error(
        "[#{SOURCE}] booking #{booking.id} could not be released: #{e.class}: #{e.message}"
      )
      { status: :failed, booking_id: booking.id }
    end

    def releasable?(booking)
      booking.payment_due_at.present? &&
        booking.payment_due_at <= @now &&
        RELEASABLE_STATUSES.include?(booking.status) &&
        UNPAID_PAYMENT_STATUSES.include?(booking.payment_status) &&
        !protected_by_submission?(booking)
    end

    # A slip already uploaded and not yet reviewed stops the clock. A rejected
    # one does not: rejection restarts it, and the deadline is extended by the
    # time the hotel spent reviewing (see ArPaymentSubmissions::Reject).
    def protected_by_submission?(booking)
      ArPaymentSubmission.pending.for_booking(booking).exists?
    end

    def reason_for(booking)
      "Payment not received by #{booking.payment_due_at.in_time_zone(booking.hotel.hotel_time_zone).strftime('%d %b %Y %H:%M %Z')}."
    end

    def skip(booking)
      Rails.logger.info("[#{SOURCE}] booking #{booking.id} no longer releasable; left alone")
      { status: :skipped, booking_id: booking.id }
    end

    def failure(booking, result)
      Rails.logger.error("[#{SOURCE}] booking #{booking.id} cancellation refused: #{result.error}")
      { status: :failed, booking_id: booking.id }
    end
  end
end
