# frozen_string_literal: true

module Bookings
  # Which agent bookings are still held against a payment deadline, and which of
  # them the clock has stopped for.
  #
  # The sweeper cancels these and the reminder scheduler writes to them, and they
  # must agree about both questions. A reminder for a booking the sweeper has
  # already spared, or silence before a cancellation, are the two ways this can
  # be wrong, and both come from two copies of the same predicate drifting apart.
  module PaymentHoldScope
    # Releasable by the sweeper. Deliberately confirmed-only: once the desk has
    # checked the guest in, the rooms are occupied and cancelling the booking
    # would take a room out from under someone standing in it. The debt does not
    # go away, but it stops being an inventory problem and becomes a folio one.
    HELD_STATUSES = %w[confirmed].freeze

    # Checked in and still unpaid. Not releasable, but still owed, and still the
    # agency's to settle -- so the badges and the agent's own list must keep
    # saying so rather than falling silent at check-in.
    IN_HOUSE_STATUSES = %w[checked_in].freeze

    # Every status in which an agent booking still owes money.
    SETTLING_STATUSES = (HELD_STATUSES + IN_HOUSE_STATUSES).freeze

    UNPAID_PAYMENT_STATUSES = %w[pending failed].freeze

    module_function

    # Confirmed, unpaid, corporate, and carrying a deadline. Wall-clock
    # throughout, deliberately: see Bookings::PaymentHold.
    def held(relation: Booking.all)
      relation
        .where.not(payment_due_at: nil)
        .where(status: HELD_STATUSES)
        .where(payment_status: UNPAID_PAYMENT_STATUSES)
        .where.not(hotel_corporate_account_id: nil)
    end

    # Unpaid and carrying a deadline, whether or not the guest has arrived. This
    # is the money question; `held` is the inventory one, and they part company
    # at check-in.
    def owing(relation: Booking.all)
      relation
        .where.not(payment_due_at: nil)
        .where(status: SETTLING_STATUSES)
        .where(payment_status: UNPAID_PAYMENT_STATUSES)
        .where.not(hotel_corporate_account_id: nil)
    end

    # A slip already uploaded and not yet looked at stops the clock. The agent
    # has done their part, so they are neither cancelled nor chased while the
    # hotel's review queue runs.
    #
    # A rejected slip does not protect anything: rejection restarts the clock,
    # extended by the time the review took (ArPaymentSubmission#reject!).
    def protected_by_submission?(booking)
      ArPaymentSubmission.pending.for_booking(booking).exists?
    end
  end
end
