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
          widths: [ 15, 22, 10, 24, 24, 10, 36, 22, 22, 22 ],
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
          headers: HousekeepingTasksExportTable::HEADERS,
          rows: @table.rows,
          column_types: HousekeepingTasksExportTable::COLUMN_TYPES,
          total_row: nil,
          empty_message: "No rooms found for the selected filters."
        )
      end
    end
  end
end
