# frozen_string_literal: true

module Deposits
  class SyncBookingPaymentStatus
    # Also settles the booking's payment schedule, so every path that moves the
    # booking's payment status -- a slip approved, a deposit applied or reversed
    # -- moves its instalments and deadline with it. Without that a booking could
    # read as part paid while its deposit stage stayed pending, and be released
    # for a payment it had made. `folio_transaction` and `user` say what paid a
    # stage, when the caller knows.
    def self.call(booking, folio_transaction: nil, user: nil)
      payments = Bookings::PaymentProgress.new(booking).paid_total
      status = if payments <= 0
        "pending"
      elsif payments >= booking.total_amount
        "captured"
      else
        "partial"
      end
      booking.update!(payment_status: status)
      Bookings::SettlePaymentInstalments.call(booking: booking, folio_transaction: folio_transaction, user: user)
    end
  end
end
