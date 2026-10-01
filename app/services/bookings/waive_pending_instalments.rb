# frozen_string_literal: true

module Bookings
  # Closes off the stages still owed when a booking is cancelled: nothing more is
  # due on rooms that have gone back on sale. Waived rather than deleted, so the
  # schedule the agent was given stays on record; stages already paid or
  # refunded are left exactly as they are.
  class WaivePendingInstalments
    NOTE = "Booking cancelled"

    def self.call(...) = new(...).call

    def initialize(booking)
      @booking = booking
    end

    def call
      @booking.payment_instalments.pending.find_each do |instalment|
        instalment.update!(status: "waived", note: NOTE)
      end
      SyncPaymentDeadline.call(@booking)
    end
  end
end
