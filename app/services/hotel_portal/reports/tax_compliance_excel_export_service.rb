# frozen_string_literal: true

module HotelPortal
  module Reports
    class TaxComplianceExcelExportService
      def initialize(hotel:, report:, type:)
        @hotel = hotel
        @report = report
        @table = TaxComplianceExportTable.new(report: report, type: type)
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: @table.title, period_label: period_label).generate do |builder|
          sheet = builder.add_sheet(name: @table.section_title, widths: Array.new(@table.headers.size, 18), orientation: :landscape)
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: @table.summary_metrics.map { |label, value, unit| [ label, value, unit == :currency ? currency : nil ] })
          builder.add_table(sheet: sheet, section_title: @table.section_title, headers: @table.headers, rows: @table.rows,
            column_types: @table.column_types, total_row: @table.total_row, empty_message: @table.empty_message)
        end
      end

      private

      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
