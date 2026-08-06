# frozen_string_literal: true

module HotelPortal
  module Reports
    class NotificationLogPdfExportService
      def initialize(hotel:, logs:, period_label:)
        @hotel = hotel
        @table = NotificationLogExportTable.new(logs: logs)
        @period_label = period_label
      end

      def generate
        builder = Exports::PdfReportBuilder.new(hotel: @hotel, title: "Notification Logs", period_label: @period_label, page_layout: :landscape)
        builder.add_header
        builder.add_summary([ [ "Records", @table.record_count.to_s ] ])
        builder.add_table(
          section_title: "Delivery Attempts", headers: @table.pdf_headers,
          rows: @table.pdf_rows.map { |row| [ row[0].strftime("%d %b %Y %H:%M"), *row.drop(1) ] },
          numeric_columns: [], total_row: nil, empty_message: "No notification logs found for the selected filters."
        )
        builder.render
      end
    end
  end
end
