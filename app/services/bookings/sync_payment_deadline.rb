# frozen_string_literal: true

module Bookings
  # Keeps bookings.payment_due_at equal to what the sweeper, the reminders and
  # the agent's portal all read: the deadline of the next stage still owed.
  #
  # With a schedule, that is the earliest pending instalment, and nil once none
  # is left. A booking made before schedules existed carries one deadline for
  # the whole amount and keeps it until the booking is paid in full -- a partial
  # payment does not release the agent from the rest.
  #
  # This is the only writer of the cached deadline after a booking is created, so
  # the cache cannot drift from the instalments it summarises.
  class SyncPaymentDeadline
    def self.call(...) = new(...).call

    def initialize(booking)
      @booking = booking
    end

    def call
      if @booking.payment_instalments.exists?
        @booking.update!(payment_due_at: @booking.payment_instalments.pending.minimum(:due_at))
      elsif @booking.payment_status == "captured"
        @booking.update!(payment_due_at: nil)
      end
    end
  end
end
