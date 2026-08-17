# frozen_string_literal: true

module HotelPortal
  module Reports
    class OutstandingBalancePdfExportService
      def initialize(hotel:, report:, prepared_by:)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Outstanding Balance Report", period_label: period_label, prepared_by: @prepared_by, page_layout: :landscape)
        builder.add_header
        builder.add_summary([ [ "Outstanding Bookings", @report.totals[:booking_count].to_s ], [ "Outstanding Amount", "#{currency} #{money(@report.totals[:outstanding_amount])}" ] ])
        builder.add_table(
          section_title: "Outstanding Bookings", headers: OutstandingBalanceExcelExportService::HEADERS,
          rows: @report.rows.map { |row| [ row[:guest_name], row[:confirmation_token], row[:stay_dates], row[:room_details], row[:room_numbers], row[:payment_status], money(row[:outstanding_amount]), row[:latest_note].presence || "-" ] },
          numeric_columns: [ 6 ], total_row: [ "TOTAL", nil, nil, nil, nil, nil, money(@report.totals[:outstanding_amount]), nil ],
          empty_message: "No outstanding bookings for the selected period."
        )
        builder.render
      end

      private

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def money(value) = Exports::PdfTheme.money(value)
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
