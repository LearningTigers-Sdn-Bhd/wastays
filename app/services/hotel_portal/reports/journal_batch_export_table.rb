# frozen_string_literal: true

module HotelPortal
  module Reports
    class JournalBatchExportTable
      HEADERS = [ "Business Date", "General Ledger Code (GL Code)", "Type", "Debit", "Credit", "Description", "Finalized At" ].freeze

      attr_reader :rows, :total_debit, :total_credit, :batch_count

      def initialize(batches:)
        materialized_batches = batches.to_a
        @batch_count = materialized_batches.size
        @rows = materialized_batches.flat_map do |batch|
          batch.entries.map do |entry|
            [ batch.business_date, entry.gl_code, entry.transaction_type, entry.debit_amount.to_d, entry.credit_amount.to_d, entry.description, batch.finalized_at ]
          end
        end.freeze
        @total_debit = @rows.sum { |row| row[3] }
        @total_credit = @rows.sum { |row| row[4] }
        freeze
      end
    end
  end
end
