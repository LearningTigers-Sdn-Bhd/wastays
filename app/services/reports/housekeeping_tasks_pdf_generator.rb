# frozen_string_literal: true

module Reports
  class HousekeepingTasksPdfGenerator
    def initialize(hotel:, rooms:, selected_date:, prepared_by:, visible_columns:)
      @hotel = hotel
      @table = HousekeepingTasksExportTable.new(rooms:, visible_columns:)
      @selected_date = selected_date
      @prepared_by = prepared_by
    end

    def call
      builder = HotelPortal::Reports::Exports::PdfReportBuilder.new(
        hotel: @hotel,
        title: "Housekeeping Tasks",
        period_label: @selected_date.strftime("%d %b %Y"),
        period_label_title: "Selected date",
        prepared_by: @prepared_by,
        page_layout: :landscape,
        frame_variant: :compact
      )
      builder.add_header
      builder.add_table(
        section_title: "Room Details",
        section_meta: "#{@table.room_count} #{@table.room_count == 1 ? 'room' : 'rooms'}",
        headers: @table.pdf_headers,
        rows: @table.pdf_rows,
        numeric_columns: @table.numeric_columns,
        total_row: nil,
        empty_message: "No rooms found for the selected filters.",
        column_widths: @table.pdf_column_widths(builder.content_width)
      )
      builder.render
    end
  end
end
