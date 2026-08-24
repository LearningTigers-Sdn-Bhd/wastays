# frozen_string_literal: true

module Reports
  class HousekeepingTasksExportTable
    attr_reader :rows, :columns, :rooms

    def initialize(rooms:, visible_columns:)
      @rooms = rooms
      @columns = HousekeepingTasks::Columns.selected(visible_columns)
      raise ArgumentError, "at least one visible column is required" if columns.empty?

      @rows = rooms.map { |room| row_for(room).values_at(*column_keys) }
    end

    def room_count = rows.size
    def assigned_count = rooms.count { |room| room[:assigned_to].present? }
    def headers = columns.map(&:export_label)
    def pdf_headers = columns.map(&:pdf_label)
    def column_types = columns.map(&:type)
    def excel_widths = columns.map(&:excel_width)
    def numeric_columns = column_types.each_index.select { |index| column_types[index] == :integer }

    def pdf_rows = rows

    def pdf_column_widths(content_width)
      total = columns.sum(&:pdf_width).to_f
      columns.map { |column| column.pdf_width * content_width / total }
    end

    private

    def column_keys = columns.map(&:key)

    def row_for(room)
      booking = room[:booking]
      {
        "room_number" => room[:room_number].to_s,
        "room_type" => room[:room_type].name.to_s,
        "pax" => room[:pax].presence || "—",
        "room_status" => room[:room_status_label].to_s,
        "assigned_to" => room[:assigned_to]&.name.presence || "Unassigned",
        "booking_status" => room[:booking_status_label].to_s,
        "arrival" => arrival_for(booking),
        "departure" => departure_for(booking),
        "nights" => booking&.duration_in_nights,
        "remarks" => room[:notes].to_s
      }
    end

    def arrival_for(booking)
      return "—" unless booking

      display_datetime(booking.checked_in_at) || display_date(booking.check_in)
    end

    def departure_for(booking)
      return "—" unless booking

      display_datetime(booking.checked_out_at || booking.check_out)
    end

    def display_datetime(value)
      value&.strftime("%d %b %Y, %I:%M %p")
    end

    def display_date(value)
      value&.to_date&.strftime("%d %b %Y") || "—"
    end
  end
end
