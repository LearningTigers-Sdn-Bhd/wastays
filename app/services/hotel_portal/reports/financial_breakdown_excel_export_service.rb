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
          if @report.currency_totals.empty?
            add_sheet(builder, currency, nil)
          else
            @report.currency_totals.each { |totals| add_sheet(builder, totals.fetch(:currency), totals) }
          end
        end
      end

      private

      def add_sheet(builder, currency_code, totals)
        sheet = builder.add_sheet(
          name: "#{currency_code} Financial Breakdown",
          widths: [ 20, 18, 24, 14, 14, 14, 14, 14, 14, 14, 12 ],
          orientation: :landscape
        )
        builder.add_header(sheet: sheet, subtitle: currency_code)
        builder.add_summary(sheet: sheet, metrics: summary_metrics(totals, currency_code)) if totals
        builder.add_table(
          sheet: sheet,
          section_title: "Booking Details",
          headers: FinancialBreakdownCsvExportService::HEADERS,
          rows: rows_for(currency_code).map do |row|
            row.values_at(:booking_number, :confirmation_code, :guest_name, :status, :check_in, :check_out, :gross, :taxes, :margin, :net, :currency)
          end,
          column_types: %i[text text text text date date money money money money text],
          total_row: totals && [ "TOTAL", nil, nil, nil, nil, nil, *totals.values_at(:gross, :taxes, :margin, :net), currency_code ],
          empty_message: "No bookings found for the selected criteria."
        )
      end

      def summary_metrics(totals, currency_code)
        [
          [ "Gross Price", totals.fetch(:gross), currency_code ],
          [ "Taxes", totals.fetch(:taxes), currency_code ],
          [ "Commission", totals.fetch(:margin), currency_code ],
          [ "Net Payout", totals.fetch(:net), currency_code ]
        ]
      end

      def rows_for(currency_code)
        @report.rows.select { |row| row.fetch(:currency) == currency_code }
      end

      def period_label = "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
