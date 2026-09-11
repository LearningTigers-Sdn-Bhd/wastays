# frozen_string_literal: true

module HotelPortal
  module Reports
    # Builds the record selection of the cashier activity table.
    module CashierActivitySelection
      module_function

      def new(report:, group_by:, transaction_ids:, group_values:, excluded_transaction_ids:)
        table = CashierActivityTable.new(report:, group_by:)
        RecordSelection.new(
          records: report.transactions,
          record_id: ->(transaction) { transaction.id },
          group_key: ->(transaction) { table.group_key(transaction) },
          ids: transaction_ids,
          group_values:,
          excluded_ids: excluded_transaction_ids
        )
      end
    end
  end
end
