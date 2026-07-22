# frozen_string_literal: true

module HotelPortal
  module Reports
    class TaxComplianceCsvExportService
      def initialize(report:, type:)
        @table = TaxComplianceExportTable.new(report: report, type: type)
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << @table.headers
          @table.rows.each { |row| csv << format_row(row) }
          csv << format_row(@table.total_row)
        end
      end

      private

      def format_row(row)
        row.each_with_index.map do |value, index|
          case @table.column_types[index]
          when :date then value.present? ? @csv.date(value) : nil
          when :money then value.present? ? @csv.money(value) : nil
          else @csv.text(value)
          end
        end
      end
    end
  end
end
