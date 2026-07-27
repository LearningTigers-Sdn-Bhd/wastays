# frozen_string_literal: true

module Deposits
  class SyncBookingPaymentStatus
    def self.call(booking)
      payments = booking.booking_folios.joins(:folio_transactions)
        .where(folio_transactions: { transaction_type: "payment" })
        .sum("folio_transactions.amount")
      status = if payments <= 0
        "pending"
      elsif payments >= booking.total_amount
        "captured"
      else
        "partial"
      end
      booking.update!(payment_status: status)
    end
  end
end
