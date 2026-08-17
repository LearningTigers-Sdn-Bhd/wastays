# frozen_string_literal: true

module HotelPortal
  module Reports
    class FinancialBreakdownPdfExportService
      def initialize(hotel:, report:, prepared_by:)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Financial Breakdown", period_label: period_label, prepared_by: @prepared_by, page_layout: :landscape)
        builder.add_header
        builder.add_summary([ [ "Gross", amount(:gross) ], [ "Taxes", amount(:taxes) ], [ "Margin", amount(:margin) ], [ "Net Payout", amount(:net) ] ])
        builder.add_table(
          section_title: "Booking Details", headers: FinancialBreakdownCsvExportService::HEADERS,
          rows: @report.rows.map { |row| [ row[:booking_reference], row[:guest_name], row[:status].to_s.titleize, date(row[:check_in]), date(row[:check_out]), money(row[:gross]), money(row[:taxes]), money(row[:margin]), money(row[:net]), row[:currency].presence || currency ] },
          numeric_columns: [ 5, 6, 7, 8 ],
          total_row: [ "TOTAL", nil, nil, nil, nil, *@report.totals.values_at(:gross, :taxes, :margin, :net).map { |value| money(value) }, currency ],
          empty_message: "No bookings found for the selected criteria."
        )
        builder.render
      end

      private

      def amount(key) = "#{currency} #{money(@report.totals[key])}"
      def money(value) = format("%.2f", value.to_d)
      def date(value) = value&.strftime("%d %b %Y") || "-"
      def period_label = "#{date(@report.start_date)} - #{date(@report.end_date)}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
