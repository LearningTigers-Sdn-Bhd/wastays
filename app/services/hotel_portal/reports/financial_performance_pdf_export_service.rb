# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialPerformancePdfExportService
      HEADERS = FinancialPerformanceCsvExportService::HEADERS

      def initialize(hotel:, report:, prepared_by:)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(
          hotel: @hotel,
          title: "Financial Summary Report",
          period_label: period_label,
          prepared_by: @prepared_by,
          page_layout: :landscape
        )
        builder.add_header
        builder.add_summary(summary_metrics)
        builder.add_table(
          section_title: "Daily Performance",
          headers: HEADERS,
          rows: detail_rows,
          numeric_columns: [ 1, 3, 4, 5 ],
          total_row: total_row,
          empty_message: "No financial activity found for this period."
        )
        builder.render
      end

      private

      def summary_metrics
        [
          [ "Gross Bookings", amount_label(@report.totals[:gross]) ],
          [ "Total Margin", amount_label(@report.totals[:margin]) ],
          [ "Net Earnings", amount_label(@report.totals[:net]) ],
          [ "Total Reservations", @report.totals[:booking_count].to_s ]
        ]
      end

      def detail_rows
        @report.rows.map do |row|
          [
            row[:date].strftime("%d %b %Y"), row[:booking_count].to_s, currency,
            money(row[:gross]), money(row[:margin]), money(row[:net])
          ]
        end
      end

      def total_row
        [
          "TOTAL", @report.totals[:booking_count].to_s, currency,
          money(@report.totals[:gross]), money(@report.totals[:margin]), money(@report.totals[:net])
        ]
      end

      def period_label
        return @report.start_date.strftime("%d %b %Y") if @report.start_date == @report.end_date

        "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      end

      def amount_label(value)
        "#{currency} #{money(value)}"
      end

      def money(value) = Exports::PdfTheme.money(value)

      def currency
        @hotel.default_currency.presence || "MYR"
      end
    end
  end
end
