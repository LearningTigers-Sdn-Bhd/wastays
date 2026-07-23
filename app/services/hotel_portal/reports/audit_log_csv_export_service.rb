# frozen_string_literal: true

module HotelPortal
  module Reports
    class AuditLogCsvExportService
      def initialize(logs:)
        @table = AuditLogExportTable.new(logs: logs)
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << AuditLogExportTable::HEADERS
          @table.rows.each do |row|
            csv << [ @csv.text(row[0].iso8601), *csv_text(row.drop(1)) ]
          end
        end
      end

      private

      def csv_text(values) = values.map { |value| @csv.text(value) }
    end
  end
end
