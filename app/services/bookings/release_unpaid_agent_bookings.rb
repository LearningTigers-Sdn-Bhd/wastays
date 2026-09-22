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
    RELEASABLE_STATUSES = PaymentHoldScope::HELD_STATUSES
    UNPAID_PAYMENT_STATUSES = PaymentHoldScope::UNPAID_PAYMENT_STATUSES

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

    # Wall-clock, deliberately: see Bookings::PaymentHold. The scope is shared
    # with the reminder scheduler so the two cannot disagree about which
    # bookings are held.
    def due_bookings
      scope = PaymentHoldScope.held.where(payment_due_at: ..@now)
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

        close_group_if_emptied(booking)
        notify(booking)
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

    # A multi-room agent booking is several bookings under one group
    # (CorporatePortal::CreateAgentBooking), each with its own deadline. When
    # the last of them is released, the group is left behind reading "active"
    # unless something closes it -- so the desk's group list would still show a
    # stay nobody is holding rooms for.
    def close_group_if_emptied(booking)
      group = booking.group_booking
      return if group.blank? || group.status == "cancelled"
      return if group.bookings.where.not(status: "cancelled").exists?

      group.update!(status: "cancelled")
    end

    def releasable?(booking)
      booking.payment_due_at.present? &&
        booking.payment_due_at <= @now &&
        RELEASABLE_STATUSES.include?(booking.status) &&
        UNPAID_PAYMENT_STATUSES.include?(booking.payment_status) &&
        !protected_by_submission?(booking)
    end

    def protected_by_submission?(booking)
      PaymentHoldScope.protected_by_submission?(booking)
    end

    def reason_for(booking)
      "Payment not received by #{booking.payment_due_at.in_time_zone(booking.hotel.hotel_time_zone).strftime('%d %b %Y %H:%M %Z')}."
    end

    # The agent is told their rooms are gone, and the desk is told on the bell,
    # because a reservation that disappears overnight is otherwise a phone call
    # nobody can answer. Neither failure is allowed to undo the release itself.
    def notify(booking)
      ::Notifications::QueueAgentPaymentNotice.call(
        booking: booking,
        notification_type: "agent_booking_released",
        trigger_event: SOURCE,
        idempotency_key: "agent_booking_released:#{booking.id}",
        extra: { released_at: @now.iso8601 }
      )
      ::Notifications::PublishAgentPaymentStaffNotification.call(booking: booking, event: :released)
    rescue StandardError => e
      Rails.logger.error("[#{SOURCE}] booking #{booking.id} released but not notified: #{e.class}: #{e.message}")
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
