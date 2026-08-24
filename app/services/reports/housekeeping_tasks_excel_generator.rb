# frozen_string_literal: true

module Reports
  class HousekeepingTasksExcelGenerator
    def initialize(hotel:, rooms:, selected_date:, visible_columns:)
      @hotel = hotel
      @table = HousekeepingTasksExportTable.new(rooms:, visible_columns:)
      @selected_date = selected_date
    end

    def call
      HotelPortal::Reports::Exports::ExcelReportBuilder.new(
        hotel: @hotel, title: "Housekeeping Tasks", period_label: @selected_date.strftime("%d %b %Y")
      ).generate do |builder|
        sheet = builder.add_sheet(
          name: "Housekeeping Tasks",
          widths: @table.excel_widths,
          orientation: :landscape
        )
        builder.add_header(sheet: sheet)
        builder.add_summary(
          sheet: sheet,
          metrics: [ [ "Rooms", @table.room_count, nil ], [ "Assigned", @table.assigned_count, nil ] ]
        )
        builder.add_table(
          sheet: sheet,
          section_title: "Room Details",
          headers: @table.headers,
          rows: @table.rows,
          column_types: @table.column_types,
          total_row: nil,
          empty_message: "No rooms found for the selected filters."
        )
      end
    end
  end
end
