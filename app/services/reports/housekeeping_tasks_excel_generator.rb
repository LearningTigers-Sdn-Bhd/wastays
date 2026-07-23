# frozen_string_literal: true

module Reports
  class HousekeepingTasksExcelGenerator
    def initialize(hotel:, room_groups:, selected_date:)
      @hotel = hotel
      @table = HousekeepingTasksExportTable.new(room_groups: room_groups)
      @selected_date = selected_date
    end

    def call
      HotelPortal::Reports::Exports::ExcelReportBuilder.new(
        hotel: @hotel, title: "Housekeeping Tasks", period_label: @selected_date.strftime("%d %b %Y")
      ).generate do |builder|
        sheet = builder.add_sheet(
          name: "Housekeeping Tasks",
          widths: [ 15, 22, 22, 18, 16, 16, 16, 12, 34, 18, 24 ],
          orientation: :landscape
        )
        builder.add_header(sheet: sheet)
        builder.add_summary(
          sheet: sheet,
          metrics: [ [ "Tasks", @table.task_count, nil ], [ "Assigned", @table.assigned_count, nil ] ]
        )
        builder.add_table(
          sheet: sheet,
          section_title: "Task Details",
          headers: HousekeepingTasksExportTable::HEADERS,
          rows: @table.rows,
          column_types: HousekeepingTasksExportTable::COLUMN_TYPES,
          total_row: nil,
          empty_message: "No housekeeping tasks found for the selected filters."
        )
      end
    end
  end
end
