# frozen_string_literal: true

module Folios
  class RecordPaymentFromGateway
    def self.call(payment_transaction)
      return unless payment_transaction.status == "captured"

      booking = payment_transaction.booking
      return unless booking&.booking_folio
      return if already_recorded?(booking.booking_folio, payment_transaction)

      amount = payment_transaction.amount_subunits.to_d / 100.0
      Folios::InsertTransaction.new(
        booking_folio: booking.booking_folio,
        amount: amount,
        transaction_type: :payment,
        category: "gateway_payment",
        user: nil, # System/Gateway payment
        description: "Payment via #{payment_transaction.gateway} (#{payment_transaction.external_reference})",
        posting_date: payment_transaction.captured_at&.to_date || Time.current.to_date,
        options: {
          metadata: { payment_transaction_id: payment_transaction.id },
          override_night_audit: true # Always allow gateway payments even on closed dates
        }
      ).call
    end

    def self.already_recorded?(folio, payment_transaction)
      folio.folio_transactions.payment.where("metadata->>'payment_transaction_id' = ?", payment_transaction.id.to_s).exists?
    end
  end
end
