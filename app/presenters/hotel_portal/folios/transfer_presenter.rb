# frozen_string_literal: true

module HotelPortal
  module Folios
    class TransferPresenter
      def initialize(rows:)
        @rows = rows
        charges = rows.select { |row| row.charge? && !::Folios::Transactions::MovementPolicy.attached_tax?(row) }
        candidates = ::Folios::Transactions::AttachedTaxTransactions.candidates_for(charges).to_a
        @taxes = charges.to_h { |charge| [ charge.id, ::Folios::Transactions::AttachedTaxTransactions.call(charge, candidates:) ] }
        @surcharges = rows.select(&:payment?).to_h { |payment| [ payment.id, [] ] }
        charges.select { |row| surcharge?(row) }.each do |charge|
          payments = rows.select { |row| row.payment? && surcharge_matches?(charge, row) }
          @surcharges[payments.sole.id] << charge if payments.one?
        end
        @child_ids = (@taxes.values.flatten + @surcharges.values.flatten).map(&:id)
      end

      def rows_for(folio)
        rows.select { |row| row.booking_folio_id == folio.id }
      end

      def rows = @rows.reject { |row| @child_ids.include?(row.id) }
      def taxes(row) = @taxes.fetch(row.id, [])
      def surcharges(row) = @surcharges.fetch(row.id, [])
      def total_with_taxes(row) = row.amount + taxes(row).sum(&:amount)
      def surcharge?(row) = row.metadata["posting_source"] == "payment_surcharge"

      def tax_label(row)
        row.metadata.dig("tax_line", "name").presence || row.posted_transaction_code_name.presence || row.description
      end

      private

      def surcharge_matches?(charge, payment)
        return false unless charge.booking_folio_id == payment.booking_folio_id && charge.source_booking_id == payment.source_booking_id
        return true if payment.metadata["payment_operation_key"].present? && charge.operation_key == payment.metadata["payment_operation_key"]

        deposit_key = payment.metadata["deposit_operation_key"].to_s
        surcharge_key = charge.operation_key.to_s
        return false if deposit_key.blank? || !surcharge_key.end_with?(":surcharge")

        receipt_key = surcharge_key.delete_suffix(":surcharge")
        deposit_key == receipt_key || deposit_key.match?(/\A#{Regexp.escape(receipt_key)}:\d+:\d+\z/)
      end
    end
  end
end
