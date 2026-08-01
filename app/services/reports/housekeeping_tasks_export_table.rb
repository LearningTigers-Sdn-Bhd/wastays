# frozen_string_literal: true

module Reports
  class HousekeepingTasksExportTable
    HEADERS = [
      "Room Number", "Room Type", "Pax", "Room Status", "Assigned To",
      "Booking Status", "Arrival", "Departure", "Nights", "Remarks"
    ].freeze
    COLUMN_TYPES = %i[text text text text text text text text integer text].freeze
    PDF_HEADERS = [ "Room", "Room Type", "Pax", "Room Status", "Assigned To",
                    "Booking Status", "Arrival", "Departure", "Nights", "Remarks" ].freeze
    PDF_COLUMN_WIDTHS = [ 48, 80, 38, 75, 80, 85, 75, 75, 42, 140 ].freeze

    attr_reader :rows

    def initialize(room_groups:)
      @rows = build_rows(room_groups)
    end

    def room_count = rows.size
    def assigned_count = rows.count { |row| row[4] != "Unassigned" }

    def pdf_rows = rows

    private

    def build_rows(room_groups)
      room_groups.flat_map do |group|
        group[:rooms].map { |room| row_for(group, room) }
      end
    end

    def row_for(group, room)
      booking = room[:booking]
      [
        room[:room_number].to_s,
        group[:room_type].name.to_s,
        room[:pax].presence || "—",
        room[:room_status_label].to_s,
        room[:assigned_to]&.name.presence || "Unassigned",
        room[:booking_status_label].to_s,
        arrival_for(booking),
        departure_for(booking),
        booking&.duration_in_nights,
        room[:notes].to_s
      ]
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
