# frozen_string_literal: true

module HotelPortal
  module Reports
    class RefundReportPdfExportService
      def initialize(hotel:, report:, prepared_by:)
        @hotel = hotel
        @report = report
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Refund Report", period_label: period_label, prepared_by: @prepared_by, page_layout: :landscape)
        builder.add_header
        builder.add_summary([ [ "Refund Count", @report.totals[:refund_count].to_s ], [ "Total Refund", "#{currency} #{money(@report.totals[:total_amount])}" ] ])
        builder.add_table(
          section_title: "Refund Records", headers: RefundReportExcelExportService::HEADERS,
          rows: @report.rows.map { |row| [ row[:date].strftime("%d %b %Y"), row[:room], row[:guest_name], row[:booking_reference], row[:refund_method], row[:reference], row[:status], row[:reason], money(row[:refund_amount]) ] },
          numeric_columns: [ 8 ], total_row: [ "TOTAL", nil, nil, nil, nil, nil, nil, nil, money(@report.totals[:total_amount]) ],
          empty_message: "No refund data for the selected period."
        )
        builder.render
      end

      private

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def money(value) = format("%.2f", value.to_d)
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
