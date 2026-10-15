# frozen_string_literal: true

module CorporatePortal
  # The one definition of "this agent still owes money on this booking".
  #
  # The dashboard and the bookings list both have to agree about which bookings
  # still owe, so the predicate lives in one place rather than being re-derived
  # at each call site. It reads Bookings::PaymentHoldScope.owing, the same module
  # Bookings::ReleaseUnpaidAgentBookings reads for its narrower question.
  #
  # A slip already with the hotel does not leave this scope. The booking is still
  # unpaid and the agent should still see it; what changes is the clock, which
  # CorporatePortal::BookingPaymentPresenter reports as "under review".
  #
  # Neither does checking the guest in. The sweeper stops at that point -- an
  # occupied room cannot be released -- but the agency still owes for the stay,
  # and dropping the booking here is what used to let an unpaid one go quiet
  # between arrival and the argument at the checkout counter.
  class BookingsAwaitingPaymentQuery
    def self.call(...) = new(...).call

    def initialize(relation:)
      @relation = relation
    end

    def call
      ::Bookings::PaymentHoldScope
        .owing(relation: @relation)
        .order(:payment_due_at)
    end

    # Bookings whose deadline has already gone by. A confirmed one is not
    # cancelled yet -- the sweeper runs every five minutes -- so the agent may
    # still be able to save it. A checked-in one is past saving in that sense:
    # the rooms are safe, and what is left is a bill.
    def overdue(now: Time.current)
      call.where(payment_due_at: ..now)
    end
  end
end
