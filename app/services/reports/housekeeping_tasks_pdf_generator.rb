# frozen_string_literal: true

module Reports
  class HousekeepingTasksPdfGenerator
    def initialize(hotel:, room_groups:, selected_date:)
      @hotel = hotel
      @table = HousekeepingTasksExportTable.new(room_groups: room_groups)
      @selected_date = selected_date
    end

    def call
      builder = HotelPortal::Reports::Exports::PdfReportBuilder.new(
        hotel: @hotel,
        title: "Housekeeping Tasks",
        period_label: @selected_date.strftime("%d %b %Y"),
        page_layout: :landscape
      )
      builder.add_header
      builder.add_summary([ [ "Tasks", @table.task_count.to_s ], [ "Assigned", @table.assigned_count.to_s ] ])
      builder.add_table(
        section_title: "Task Details",
        headers: HousekeepingTasksExportTable::PDF_HEADERS,
        rows: @table.pdf_rows,
        numeric_columns: [],
        total_row: nil,
        empty_message: "No housekeeping tasks found for the selected filters.",
        column_widths: HousekeepingTasksExportTable::PDF_COLUMN_WIDTHS
      )
      builder.render
    end
  end
end
