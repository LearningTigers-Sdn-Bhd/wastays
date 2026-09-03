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
        :start_date, :end_date, :totals, :cash_transactions,
        :mode_by_transaction_id, :section_by_transaction_id, :mode_order,
        :mode_summary_rows, :mode_totals, :currency_summary_rows, :grand_total,
        :non_cash_transactions, :non_cash_totals,
        keyword_init: true
      )

      def initialize(hotel:, start_date:, end_date:, start_time: nil, end_time: nil, transaction_ids: nil)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @start_time = parse_time_of_day(start_time)
        @end_time = parse_time_of_day(end_time)
        @transaction_ids = transaction_ids.presence
      end

      def call
        transactions = filter_by_time_range(base_scope.to_a)
        cash, non_cash = transactions.partition { |transaction| cashier_handled?(transaction) }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          totals: totals_for(cash),
          cash_transactions: group_by_mode(cash),
          mode_by_transaction_id: transactions.to_h { |transaction| [ transaction.id, mode_label_for(transaction) ] },
          section_by_transaction_id: transactions.to_h { |transaction| [ transaction.id, section_for(transaction) ] },
          mode_order: mode_order,
          mode_summary_rows: mode_summary_for(cash),
          mode_totals: mode_totals_for(cash),
          currency_summary_rows: currency_summary_for(cash),
          grand_total: grand_total_for(cash),
          non_cash_transactions: non_cash,
          non_cash_totals: totals_for(non_cash)
        )
      end

      private

      # Cash drawer money is everything hotel staff handled themselves. Online
      # gateway charges and OTA-collected credits are real money, but no cashier
      # ever counted them, so they are reported apart from the drawer total.
      def cashier_handled?(transaction)
        !gateway_movement?(transaction) && !ota_non_cash_movement?(transaction)
      end

      def gateway_movement?(transaction)
        ::Folios::Payments::GatewayOriginated.call(classification_transaction(transaction)) ||
          transaction.metadata.to_h.stringify_keys["refund_source"] == "gateway"
      end

      # The hotel decides which payment methods it takes and in which order it
      # lists them. The report follows that order rather than the alphabet, so a
      # cashier reads the report in the same order they read the payment screen.
      def mode_order
        @mode_order ||= @hotel.hotel_payment_methods
          .ordered
          .joins(:transaction_code)
          .pluck("transaction_codes.name")
      end

      def mode_rank(mode)
        mode_order.index(mode) || mode_order.size
      end

      def group_by_mode(transactions)
        transactions.sort_by.with_index do |transaction, index|
          [ mode_rank(mode_label_for(transaction)), mode_label_for(transaction), index ]
        end
      end

      def base_scope
        scope = FolioTransaction
          .payment
          .joins(booking_folio: :booking)
          .left_outer_joins(:transaction_code)
          .where(bookings: { hotel_id: @hotel.id })
          .where(posting_date: @start_date..@end_date)
        scope = scope.where(id: @transaction_ids) if @transaction_ids
        scope.includes(
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
          .sort_by { |row| [ mode_rank(row[:mode]), row[:mode], row[:section] ] }
      end

      def mode_totals_for(transactions)
        transactions
          .group_by { |t| mode_label_for(t) }
          .map { |mode, txs| { mode: mode }.merge(in_out_balance(txs)) }
          .sort_by { |row| [ mode_rank(row[:mode]), row[:mode] ] }
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

      def filter_by_time_range(transactions)
        return transactions unless @start_time || @end_time

        transactions.select do |transaction|
          reference = transaction.posted_at || transaction.created_at
          next false unless reference

          seconds = reference.seconds_since_midnight.to_i
          (@start_time.nil? || seconds >= @start_time) && (@end_time.nil? || seconds <= @end_time)
        end
      end

      def parse_time_of_day(value)
        return nil if value.blank?

        hour, minute = value.to_s.split(":").map(&:to_i)
        return nil unless hour.present? && (0..23).cover?(hour) && (0..59).cover?(minute.to_i)

        hour * 3600 + minute.to_i * 60
      end
    end
  end
end
