# frozen_string_literal: true

module HotelPortal
  module Reports
    class PoliceReportPdfExportService
      COLUMN_WIDTHS = [ 110, 46, 45, 115, 110, 70, 77, 70, 75, 59 ].freeze

      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
        @table = PoliceReportExportTable.new(report: report)
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Daily Police Report", subtitle: "Police report records", period_label: period_label, page_layout: :landscape)
        builder.add_header
        builder.add_summary([ [ "Guest stays", @table.rows.size.to_s ] ])
        builder.add_table(section_title: "Police report records", headers: @table.pdf_headers, rows: @table.pdf_rows, numeric_columns: [], total_row: nil, empty_message: "No guest stays in this selected period.", column_widths: COLUMN_WIDTHS)
        builder.render
      end

      private

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
    end
  end
end
