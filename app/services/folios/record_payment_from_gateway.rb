# frozen_string_literal: true

require "ostruct"

module Folios
  class RecordPaymentFromGateway
    def self.call(payment_transaction)
      return unless payment_transaction.status == "captured"

      booking = payment_transaction.booking
      return unless booking&.booking_folio

      folio = booking.booking_folio
      folio.with_lock do
        existing_transaction = existing_payment_transaction(folio, payment_transaction)
        return success(existing_transaction) if existing_transaction

        amount = payment_transaction.amount_subunits.to_d / 100.0
        result = Folios::InsertTransaction.new(
          booking_folio: folio,
          amount: amount,
          transaction_type: :payment,
          category: "gateway_payment",
          user: nil, # System/Gateway payment
          description: "Payment via #{payment_transaction.gateway} (#{payment_transaction.external_reference})",
          posting_date: payment_transaction.captured_at&.to_date || Time.current.to_date,
          options: posting_options(booking, payment_transaction)
        ).call

        return result if result.success?

        existing_transaction = existing_payment_transaction(folio, payment_transaction)
        existing_transaction ? success(existing_transaction) : result
      end
    rescue ActiveRecord::RecordNotUnique
      existing_transaction = existing_payment_transaction(folio, payment_transaction)
      existing_transaction ? success(existing_transaction) : failure("Gateway payment was already recorded but could not be loaded")
    end

    def self.existing_payment_transaction(folio, payment_transaction)
      folio.folio_transactions.payment
        .where("metadata->>'payment_transaction_id' = ?", payment_transaction.id.to_s)
        .first
    end

    def self.posting_options(booking, payment_transaction)
      posting_date = payment_transaction.captured_at&.to_date || Time.current.to_date
      options = { posting_source: "gateway_payment", metadata: { payment_transaction_id: payment_transaction.id } }
      return options unless NightAudit.closed_for_date?(booking.hotel_id, posting_date)

      options.merge(system_posting: true)
    end

    def self.success(transaction)
      OpenStruct.new(success?: true, transaction: transaction)
    end

    def self.failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
