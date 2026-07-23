# frozen_string_literal: true

module HotelPortal
  module Reports
    class PoliceReportCsvExportService
      def initialize(report:) = @table = PoliceReportExportTable.new(report: report)

      def generate
        Exports::CsvReportSupport.new.generate do |csv|
          csv << @table.headers
          @table.rows.each { |row| csv << row }
        end
      end
    end
  end
end
