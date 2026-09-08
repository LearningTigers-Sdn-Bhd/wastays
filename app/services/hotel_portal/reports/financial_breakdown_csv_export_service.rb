# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownCsvExportService
      def initialize(hotel:, report:, visible_columns: BookingPerformanceColumns::DEFAULT_KEYS)
        @hotel = hotel
        @report = report
        @visible_columns = visible_columns
        @csv = Exports::CsvReportSupport.new
      end

      def generate
        @csv.generate do |csv|
          csv << table_for([]).headers
          @report.totals_by_currency.each do |totals|
            table = table_for(rows_for(totals.fetch(:currency)))
            table.rows.each { |row| csv << csv_row(row, table.column_types) }
            csv << csv_row(table.total_row(totals), table.column_types, total: true)
          end
        end
      end

      private

      def csv_row(row, types, total: false)
        row.each_with_index.map do |value, index|
          next if value.nil?
          next @csv.text(value) if total && index.zero?

          case types.fetch(index)
          when :date then @csv.date(value)
          when :money then @csv.money(value)
          else @csv.text(value)
          end
        end
      end

      def rows_for(currency_code)
        @report.ordered_rows.select { |row| row.currency == currency_code }
      end

      def table_for(rows)
        BookingPerformanceExportTable.new(rows:, visible_columns: @visible_columns)
      end
    end
  end
end
