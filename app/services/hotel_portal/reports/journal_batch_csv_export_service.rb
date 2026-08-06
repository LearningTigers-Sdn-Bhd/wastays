# frozen_string_literal: true

module HotelPortal
  module Reports
    class JournalBatchCsvExportService
      def initialize(batches:)
        @table = JournalBatchExportTable.new(batches: batches)
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << JournalBatchExportTable::HEADERS
          @table.rows.each do |row|
            csv << [ @csv.date(row[0]), @csv.text(row[1]), @csv.text(row[2]), @csv.money(row[3]), @csv.money(row[4]), @csv.text(row[5]), @csv.text(row[6]&.iso8601) ]
          end
          csv << [ "TOTAL", nil, nil, @csv.money(@table.total_debit), @csv.money(@table.total_credit), nil, nil ]
        end
      end
    end
  end
end
