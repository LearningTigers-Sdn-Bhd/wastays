# frozen_string_literal: true

module HotelPortal
  module Reports
    class CashierActivityTable
      GROUPINGS = %w[handling payment_mode stage received_by].freeze
      DEFAULT_GROUPING = "handling"
      Group = Data.define(:key, :label, :transactions, :count, :balance)

      def initialize(report:, group_by: nil)
        @report = report
        @group_by = group_by.to_s.presence_in(GROUPINGS) || DEFAULT_GROUPING
      end

      attr_reader :group_by

      def groups
        report.transactions.group_by { |transaction| group_key(transaction) }
          .map do |key, transactions|
            Group.new(
              key:,
              label: group_label(transactions.first),
              transactions:,
              count: transactions.size,
              balance: transactions.sum { |transaction| transaction.amount.to_d }.round(2)
            )
          end
          .sort_by { |group| group_rank(group) }
      end

      def group_key(transaction)
        case group_by
        when "payment_mode" then report.mode_by_transaction_id.fetch(transaction.id)
        when "stage" then report.section_by_transaction_id.fetch(transaction.id)
        when "received_by" then report.received_by_key_by_transaction_id.fetch(transaction.id)
        else report.handling_by_transaction_id.fetch(transaction.id)
        end
      end

      private

      attr_reader :report

      def group_label(transaction)
        case group_by
        when "payment_mode" then report.mode_by_transaction_id.fetch(transaction.id)
        when "stage" then report.section_by_transaction_id.fetch(transaction.id)
        when "received_by"
          row_for(transaction).received_by
        else CashierSalesReport::HANDLING_LABELS.fetch(report.handling_by_transaction_id.fetch(transaction.id))
        end
      end

      def group_rank(group)
        case group_by
        when "handling"
          [ CashierSalesReport::HANDLING_ORDER.index(group.key) ]
        when "payment_mode"
          [ report.mode_order.index(group.key) || report.mode_order.size, group.label.downcase ]
        when "stage"
          [ CashierSalesReport::STAGE_ORDER.index(group.key) || CashierSalesReport::STAGE_ORDER.size ]
        when "received_by"
          [ group.label == "—" ? 1 : 0, group.label.downcase ]
        end
      end

      def row_for(transaction)
        DailyReportTransactionRow.new(
          transaction,
          settlement_mode: report.mode_by_transaction_id.fetch(transaction.id),
          section: report.section_by_transaction_id.fetch(transaction.id),
          origin: report.non_cash_origin_by_transaction_id[transaction.id],
          handling: report.handling_by_transaction_id.fetch(transaction.id),
          received_by_key: report.received_by_key_by_transaction_id.fetch(transaction.id)
        )
      end
    end
  end
end
