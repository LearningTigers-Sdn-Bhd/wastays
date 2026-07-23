# frozen_string_literal: true

module HotelPortal
  module Reports
    class PoliceReportExcelExportService
      def initialize(hotel:, report:)
        @hotel = hotel
        @report = report
        @table = PoliceReportExportTable.new(report: report)
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Daily Police Report", period_label: period_label).generate do |builder|
          sheet = builder.add_sheet(name: "Police Report", widths: Array.new(@table.headers.size, 20), orientation: :landscape)
          builder.add_header(sheet: sheet, subtitle: "Police report records")
          builder.add_summary(sheet: sheet, metrics: [ [ "Guest stays", @table.rows.size, nil ] ])
          builder.add_table(sheet: sheet, section_title: "Police report records", headers: @table.headers, rows: @table.rows, column_types: Array.new(@table.headers.size, :text), total_row: nil, empty_message: "No guest stays in this selected period.")
        end
      end

      private

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
    end
  end
end
