# frozen_string_literal: true

module HotelPortal
  module Reports
    class JournalBatchPdfExportService
      def initialize(hotel:, batches:, start_date:, end_date:, prepared_by:)
        @hotel = hotel
        @table = JournalBatchExportTable.new(batches: batches)
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @prepared_by = prepared_by
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Journal Batches", period_label: period_label, prepared_by: @prepared_by, page_layout: :landscape)
        builder.add_header
        builder.add_summary([ [ "Batches", @table.batch_count.to_s ], [ "Total Debit", amount(@table.total_debit) ], [ "Total Credit", amount(@table.total_credit) ] ])
        builder.add_table(
          section_title: "Journal Entries", headers: JournalBatchExportTable::HEADERS,
          rows: @table.rows.map { |row| [ row[0].strftime("%d %b %Y"), row[1], row[2].to_s.titleize, money(row[3]), money(row[4]), row[5].presence || "-", row[6]&.strftime("%d %b %Y %H:%M") || "-" ] },
          numeric_columns: [ 3, 4 ], total_row: [ "TOTAL", nil, nil, money(@table.total_debit), money(@table.total_credit), nil, nil ],
          empty_message: "No journal batches found for the selected period."
        )
        builder.render
      end

      private

      def period_label = @start_date == @end_date ? @start_date.strftime("%d %b %Y") : "#{@start_date.strftime('%d %b %Y')} - #{@end_date.strftime('%d %b %Y')}"
      def amount(value) = "#{currency} #{money(value)}"
      def money(value) = format("%.2f", value.to_d)
      def currency = @hotel.default_currency.presence || "MYR"
    end
  end
end
