# frozen_string_literal: true

module CorporatePortal
  # The one definition of "this agent still owes money on this booking".
  #
  # The dashboard, the bookings list and the reminder scheduler all have to agree
  # with the sweeper about which bookings are at risk, so the predicate lives in
  # one place rather than being re-derived at each call site. It deliberately
  # mirrors Bookings::ReleaseUnpaidAgentBookings#due_bookings, minus the deadline
  # having passed: these are the bookings the sweeper *will* reach.
  #
  # A slip already with the hotel does not leave this scope. The booking is still
  # unpaid and the agent should still see it; what changes is the clock, which
  # CorporatePortal::BookingPaymentPresenter reports as "under review".
  class BookingsAwaitingPaymentQuery
    HELD_STATUSES = %w[confirmed].freeze
    UNPAID_PAYMENT_STATUSES = %w[pending failed].freeze

    def self.call(...) = new(...).call

    def initialize(relation:)
      @relation = relation
    end

    def call
      @relation
        .where.not(payment_due_at: nil)
        .where(status: HELD_STATUSES)
        .where(payment_status: UNPAID_PAYMENT_STATUSES)
        .order(:payment_due_at)
    end

    # Bookings whose deadline has already gone by. They are not cancelled yet --
    # the sweeper runs every five minutes -- so the agent may still be able to
    # save them.
    def overdue(now: Time.current)
      call.where(payment_due_at: ..now)
    end
  end
end
