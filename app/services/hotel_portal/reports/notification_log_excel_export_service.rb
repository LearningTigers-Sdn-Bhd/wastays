# frozen_string_literal: true

module HotelPortal
  module Reports
    class NotificationLogExcelExportService
      def initialize(hotel:, logs:, period_label:)
        @hotel = hotel
        @table = NotificationLogExportTable.new(logs: logs)
        @period_label = period_label
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Notification Logs", period_label: @period_label).generate do |builder|
          sheet = builder.add_sheet(name: "Notification Logs", widths: [ 22, 20, 24, 28, 16, 16, 24, 40 ], orientation: :landscape)
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: [ [ "Records", @table.record_count, nil ] ])
          builder.add_table(
            sheet: sheet, section_title: "Delivery Attempts", headers: NotificationLogExportTable::HEADERS,
            rows: @table.rows, column_types: NotificationLogExportTable::COLUMN_TYPES, total_row: nil,
            empty_message: "No notification logs found for the selected filters."
          )
        end
      end
    end
  end
end
