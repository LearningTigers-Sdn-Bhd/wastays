# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialPerformanceExcelExportService
      HEADERS = FinancialPerformanceCsvExportService::HEADERS

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        Exports::ExcelReportBuilder.new(
          hotel: @hotel,
          title: "Financial Summary Report",
          period_label: period_label
        ).generate do |builder|
          sheet = builder.add_sheet(name: "Financial Summary", widths: [ 14, 12, 12, 16, 16, 16 ])
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: summary_metrics)
          builder.add_table(
            sheet: sheet,
            section_title: "Daily Performance",
            headers: HEADERS,
            rows: detail_rows,
            column_types: %i[date integer text money money money],
            total_row: total_row,
            empty_message: "No financial activity found for this period."
          )
        end
      end

      private

      def summary_metrics
        [
          [ "Gross Bookings", @report.totals[:gross], currency ],
          [ "Total Margin", @report.totals[:margin], currency ],
          [ "Net Earnings", @report.totals[:net], currency ],
          [ "Total Reservations", @report.totals[:booking_count], nil ]
        ]
      end

      def detail_rows
        @report.rows.map do |row|
          [ row[:date], row[:booking_count], currency, row[:gross], row[:margin], row[:net] ]
        end
      end

      def total_row
        [
          "TOTAL", @report.totals[:booking_count], currency,
          @report.totals[:gross], @report.totals[:margin], @report.totals[:net]
        ]
      end

      def period_label
        return @report.start_date.strftime("%d %b %Y") if @report.start_date == @report.end_date

        "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      end

      def currency
        @hotel.default_currency.presence || "MYR"
      end
    end
  end
end
