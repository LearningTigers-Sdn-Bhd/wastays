# frozen_string_literal: true

require "csv"

module HotelPortal
  module Reports
    class JournalBatchCsvExportService
      def initialize(batches:)
        @batches = batches
      end

      def generate
        CSV.generate(headers: true) do |csv|
          csv << [ "Business Date", "General Ledger Code (GL Code)", "Type", "Debit", "Credit", "Description", "Finalized At" ]

          @batches.each do |batch|
            batch.entries.each do |entry|
              csv << [
                batch.business_date,
                entry.gl_code,
                entry.transaction_type,
                entry.debit_amount,
                entry.credit_amount,
                entry.description,
                batch.finalized_at
              ]
            end
          end
        end
      end
    end
  end
end
