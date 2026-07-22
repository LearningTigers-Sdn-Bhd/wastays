# frozen_string_literal: true

module HotelPortal
  module Reports
    class NotificationLogCsvExportService
      def initialize(logs:)
        @table = NotificationLogExportTable.new(logs: logs)
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << NotificationLogExportTable::HEADERS
          @table.rows.each do |row|
            csv << [ @csv.text(row[0].iso8601), *row.drop(1).map { |value| @csv.text(value) } ]
          end
        end
      end
    end
  end
end
