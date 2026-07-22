# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownExcelExportService
      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Financial Breakdown", period_label: period_label).generate do |builder|
          sheet = builder.add_sheet(name: "Financial Breakdown", widths: [ 20, 24, 14, 14, 14, 14, 14, 14, 14, 12 ], orientation: :landscape)
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: summary_metrics)
          builder.add_table(
            sheet: sheet, section_title: "Booking Details", headers: FinancialBreakdownCsvExportService::HEADERS,
            rows: @report.rows.map { |row| row.values_at(:booking_reference, :guest_name, :status, :check_in, :check_out, :gross, :taxes, :margin, :net, :currency) },
            column_types: %i[text text text date date money money money money text],
            total_row: [ "TOTAL", nil, nil, nil, nil, *@report.totals.values_at(:gross, :taxes, :margin, :net), currency ],
            empty_message: "No bookings found for the selected criteria."
          )
        end
      end

      private

      def summary_metrics
        [ [ "Gross", @report.totals[:gross], currency ], [ "Taxes", @report.totals[:taxes], currency ], [ "Margin", @report.totals[:margin], currency ], [ "Net Payout", @report.totals[:net], currency ] ]
      end

      def period_label = "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
