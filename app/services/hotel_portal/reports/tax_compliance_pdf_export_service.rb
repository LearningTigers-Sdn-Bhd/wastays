# frozen_string_literal: true

module HotelPortal
  module Reports
    class TaxCompliancePdfExportService
      def initialize(hotel:, report:, type:, prepared_by:)
        @hotel = hotel
        @report = report
        @table = TaxComplianceExportTable.new(report: report, type: type)
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: @table.title, period_label: period_label, prepared_by: @prepared_by, page_layout: :landscape)
        builder.add_header
        builder.add_summary(@table.summary_metrics.map { |label, value, unit| [ label, unit == :currency ? "#{currency} #{money(value)}" : value.to_s ] })
        builder.add_table(section_title: @table.section_title, headers: @table.headers,
          rows: @table.rows.map { |row| format_row(row) }, numeric_columns: numeric_columns,
          total_row: format_row(@table.total_row), empty_message: @table.empty_message)
        builder.render
      end

      private

      def format_row(row)
        row.each_with_index.map do |value, index|
          next "-" if value.nil?
          case @table.column_types[index]
          when :date then value.strftime("%d %b %Y")
          when :money then money(value)
          else value.to_s
          end
        end
      end

      def numeric_columns = @table.column_types.each_index.select { |index| %i[integer money].include?(@table.column_types[index]) }
      def period_label = @report.start_date == @report.end_date ? @report.start_date.strftime("%d %b %Y") : "#{@report.start_date.strftime('%d %b %Y')} - #{@report.end_date.strftime('%d %b %Y')}"
      def money(value) = format("%.2f", value.to_d)
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
