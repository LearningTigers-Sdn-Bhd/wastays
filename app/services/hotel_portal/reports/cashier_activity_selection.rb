# frozen_string_literal: true

require "set"

module HotelPortal
  module Reports
    class CashierActivitySelection
      def initialize(report:, group_by:, transaction_ids:, group_values:, excluded_transaction_ids:)
        @report = report
        @table = CashierActivityTable.new(report:, group_by:)
        @transaction_ids = integer_set(transaction_ids)
        @group_values = Array(group_values).map(&:to_s).to_set
        @excluded_transaction_ids = integer_set(excluded_transaction_ids)
      end

      def selected_ids
        allowed = report.transactions.to_h { |transaction| [ transaction.id, transaction ] }
        grouped = allowed.values.filter_map do |transaction|
          transaction.id if group_values.include?(table.group_key(transaction))
        end
        ((transaction_ids | grouped.to_set) - excluded_transaction_ids) & allowed.keys.to_set
      end

      def selected? = transaction_ids.any? || group_values.any?

      private

      attr_reader :report, :table, :transaction_ids, :group_values, :excluded_transaction_ids

      def integer_set(values)
        Array(values).filter_map { |value| Integer(value, exception: false) }.to_set
      end
    end
  end
end
