# frozen_string_literal: true

module HotelPortal
  module Reports
    class CashierSalesReport
      ADVANCE_CATEGORY = "booking_payment"
      REFUND_SOURCE_SYSTEM_KEYS = {
        "cash" => "cash_payment",
        "bank_transfer" => "bank_payment",
        "card_terminal" => "card_payment",
        "gateway" => "gateway_manual_recovery_payment",
        "ota_reconciliation" => "ota_collected_payment"
      }.freeze

      Result = Struct.new(
        :start_date, :end_date, :totals, :advance_scope, :settlement_scope,
        :mode_by_transaction_id, :mode_summary_rows, :mode_totals, :currency_summary_rows, :grand_total,
        :ota_credit_scope, :ota_credit_totals,
        keyword_init: true
      )

      def initialize(hotel:, start_date:, end_date:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def call
        scope = base_scope
        transactions = exclude_gateway_movements(scope.to_a)
        visible_scope = scope.where(id: transactions.map(&:id))
        cash_transactions, ota_credits = transactions.partition { |transaction| !ota_non_cash_movement?(transaction) }
        advances, settlements = cash_transactions.partition { |transaction| section_for(transaction) == "Advance" }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          totals: totals_for(cash_transactions),
          advance_scope: visible_scope.where(id: advances.map(&:id)),
          settlement_scope: visible_scope.where(id: settlements.map(&:id)),
          mode_by_transaction_id: transactions.to_h { |transaction| [ transaction.id, mode_label_for(transaction) ] },
          mode_summary_rows: mode_summary_for(cash_transactions),
          mode_totals: mode_totals_for(cash_transactions),
          currency_summary_rows: currency_summary_for(cash_transactions),
          grand_total: grand_total_for(cash_transactions),
          ota_credit_scope: visible_scope.where(id: ota_credits.map(&:id)),
          ota_credit_totals: totals_for(ota_credits)
        )
      end

      private

      def exclude_gateway_movements(transactions)
        payment_transaction_ids = transactions.filter_map do |transaction|
          classification_transaction(transaction).metadata.to_h.stringify_keys["payment_transaction_id"].presence
        end
        razorpay_payment_ids = PaymentTransaction
          .where(id: payment_transaction_ids, gateway: "razorpay")
          .pluck(:id)
          .map(&:to_s)

        transactions.reject do |transaction|
          gateway_originated?(classification_transaction(transaction), razorpay_payment_ids)
        end
      end

      def gateway_originated?(transaction, razorpay_payment_ids)
        metadata = transaction.metadata.to_h.stringify_keys

        transaction.category == "gateway_payment" ||
          transaction.transaction_code&.system_key == "gateway_manual_recovery_payment" ||
          metadata["posting_source"] == "gateway_payment" ||
          metadata["payment_source"] == "gateway" ||
          metadata["refund_source"] == "gateway" ||
          razorpay_payment_ids.include?(metadata["payment_transaction_id"].to_s)
      end

      def base_scope
        FolioTransaction
          .payment
          .joins(booking_folio: :booking)
          .left_outer_joins(:transaction_code)
          .where(bookings: { hotel_id: @hotel.id })
          .where(posting_date: @start_date..@end_date)
          .includes(
            :transaction_code,
            :user,
            reversal_of_transaction: :transaction_code,
            booking_folio: [ :booking_room, :booking_billing_party, { booking: :booking_rooms } ]
          )
          .order(Arel.sql(
            "folio_transactions.posting_date DESC, folio_transactions.posted_at DESC NULLS LAST, folio_transactions.id DESC"
          ))
      end

      def totals_for(transactions)
        collected = transactions.sum { |t| t.amount.to_d.positive? ? t.amount.to_d : 0.to_d }
        refunded = transactions.sum { |t| t.amount.to_d.negative? ? t.amount.to_d.abs : 0.to_d }

        {
          movement_count: transactions.size,
          total_collected: collected.round(2),
          total_refunded: refunded.round(2),
          net_cash: (collected - refunded).round(2)
        }
      end

      def ota_non_cash_movement?(transaction)
        return true if transaction.ota_collected_credit?
        return false unless transaction.category == "refund"

        transaction.reversal_of_transaction&.ota_collected_credit? || ota_reconciliation_refund?(transaction)
      end

      def ota_reconciliation_refund?(transaction)
        return false unless transaction.metadata.to_h.stringify_keys["refund_source"] == "ota_reconciliation"

        folio = transaction.booking_folio
        folio&.folio_type == "external" && folio.payer_type == "ota" && folio.booking_billing_party&.party_kind == "ota"
      end

      def section_for(transaction)
        classification_transaction(transaction).category == ADVANCE_CATEGORY ? "Advance" : "Settlement"
      end

      def mode_label_for(transaction)
        if transaction.category == "refund"
          original_mode = transaction.reversal_of_transaction&.posted_transaction_code_name.presence
          return original_mode if original_mode

          refund_source = ::Folios::Payments::RefundSource.fetch(transaction.metadata.to_h.stringify_keys["refund_source"])
          return refund_mode_label(refund_source) if refund_source
        end

        transaction.posted_transaction_code_name.presence || transaction.category.to_s.humanize
      end

      def classification_transaction(transaction)
        return transaction unless transaction.category == "refund"

        transaction.reversal_of_transaction || transaction
      end

      def refund_mode_label(refund_source)
        system_key = REFUND_SOURCE_SYSTEM_KEYS[refund_source.key]
        refund_mode_labels[system_key].presence || refund_source.label
      end

      def refund_mode_labels
        @refund_mode_labels ||= @hotel.transaction_codes
          .where(system_key: REFUND_SOURCE_SYSTEM_KEYS.values)
          .pluck(:system_key, :name)
          .to_h
      end

      def in_out_balance(txs)
        amount_in = txs.sum { |t| t.amount.to_d.positive? ? t.amount.to_d : 0.to_d }
        amount_out = txs.sum { |t| t.amount.to_d.negative? ? t.amount.to_d.abs : 0.to_d }
        { amount_in: amount_in.round(2), amount_out: amount_out.round(2), balance: (amount_in - amount_out).round(2) }
      end

      def mode_summary_for(transactions)
        transactions
          .group_by { |t| [ mode_label_for(t), t.currency, section_for(t) ] }
          .map { |(mode, currency, section), txs| { mode: mode, currency: currency, section: section }.merge(in_out_balance(txs)) }
          .sort_by { |row| [ row[:mode], row[:section] ] }
      end

      def mode_totals_for(transactions)
        transactions
          .group_by { |t| mode_label_for(t) }
          .map { |mode, txs| { mode: mode }.merge(in_out_balance(txs)) }
          .sort_by { |row| row[:mode] }
      end

      def currency_summary_for(transactions)
        transactions
          .group_by { |t| [ t.currency, section_for(t) ] }
          .map { |(currency, section), txs| { currency: currency, section: section }.merge(in_out_balance(txs)) }
          .sort_by { |row| [ row[:currency], row[:section] ] }
      end

      def grand_total_for(transactions)
        in_out_balance(transactions)
      end
    end
  end
end
