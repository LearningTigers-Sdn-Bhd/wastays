# frozen_string_literal: true

module HotelPortal
  module Reports
    class JournalBatchExcelExportService
      def initialize(hotel:, batches:, start_date:, end_date:)
        @hotel = hotel
        @table = JournalBatchExportTable.new(batches: batches)
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Journal Batches", period_label: period_label).generate do |builder|
          sheet = builder.add_sheet(name: "Journal Batches", widths: [ 16, 24, 16, 16, 16, 34, 22 ], orientation: :landscape)
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: [ [ "Batches", @table.batch_count, nil ], [ "Total Debit", @table.total_debit, currency ], [ "Total Credit", @table.total_credit, currency ] ])
          builder.add_table(
            sheet: sheet, section_title: "Journal Entries", headers: JournalBatchExportTable::HEADERS,
            rows: @table.rows, column_types: %i[date text text money money text datetime],
            total_row: [ "TOTAL", nil, nil, @table.total_debit, @table.total_credit, nil, nil ],
            empty_message: "No journal batches found for the selected period."
          )
        end
      end

      private

      def period_label = @start_date == @end_date ? @start_date.strftime("%d %b %Y") : "#{@start_date.strftime('%d %b %Y')} - #{@end_date.strftime('%d %b %Y')}"
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
