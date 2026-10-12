# frozen_string_literal: true

module Folios
  module Transactions
    class MovementPolicy
      def self.error(transaction)
        return "Transaction has already been reversed." if transaction.voided_by_transaction_id.present?
        return "Reversal transactions cannot be transferred." if transaction.reversal_of_transaction_id.present?
        return "Source folio must be open." unless transaction.booking_folio.open?
        error = Folios::DestinationPolicy.error(booking: transaction.booking_folio.booking, folio: transaction.booking_folio)
        return error if error
        return nil if transaction.charge? && !attached_tax?(transaction)
        return "Attached taxes transfer with their parent charge." if transaction.charge?
        return "Only posted charges and supported payments can be transferred." unless transaction.payment? && transaction.amount.positive?
        return "Refunds and security deposits cannot be transferred." if transaction.category.in?(%w[refund security_deposit])

        if transaction.metadata["deposit_id"].present?
          movement = transaction.deposit_movement
          return nil if movement&.movement_type_apply? && movement.deposit.kind_prepayment? && movement.reversal.blank?

          return "Only active prepayment applications can be transferred."
        end
        gateway = Folios::Payments::GatewayOriginated.for([ transaction ])
        return "Gateway and OTA payments must use their reconciliation workflow." if gateway.call(transaction) || transaction.ota_collected_credit?
        return "OTA payments must use their reconciliation workflow." if transaction.metadata["payment_source"] == "ota"
        return nil if transaction.metadata["internal_folio_movement"] && (transaction.moved_from_transaction_id || transaction.split_from_transaction_id)
        return nil if transaction.metadata["payment_source"].in?(%w[cash bank card]) ||
          transaction.metadata["hotel_payment_method_id"].present? || transaction.category == "cash" ||
          transaction.metadata["payment_transaction_id"].present? || transaction.metadata["posting_source"] == "agent_payment_panel"

        "Payment source is not supported for transfer."
      end

      def self.attached_tax?(transaction)
        transaction.parent_transaction_id.present? || transaction.metadata["parent_folio_transaction_id"].present? ||
          transaction.metadata["parent_transaction_id"].present? || transaction.metadata["tax_line"].present?
      end
    end
  end
end
