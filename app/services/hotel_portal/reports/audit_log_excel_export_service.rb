# frozen_string_literal: true

module HotelPortal
  module Reports
    class AuditLogExcelExportService
      def initialize(hotel:, logs:, period_label:)
        @hotel = hotel
        @table = AuditLogExportTable.new(logs: logs)
        @period_label = period_label
      end

      def generate
        Exports::ExcelReportBuilder.new(hotel: @hotel, title: "Operation Audit Logs", period_label: @period_label).generate do |builder|
          sheet = builder.add_sheet(name: "Operation Logs", widths: [ 22, 22, 24, 28, 48 ], orientation: :landscape)
          builder.add_header(sheet: sheet)
          builder.add_summary(sheet: sheet, metrics: [ [ "Records", @table.record_count, nil ] ])
          builder.add_table(
            sheet: sheet, section_title: "Audit Entries", headers: AuditLogExportTable::HEADERS,
            rows: @table.rows, column_types: AuditLogExportTable::COLUMN_TYPES, total_row: nil,
            empty_message: "No operation logs found for the selected filters."
          )
        end
      end
    end
  end
end
