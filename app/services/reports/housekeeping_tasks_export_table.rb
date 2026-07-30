# frozen_string_literal: true

module Reports
  class HousekeepingTasksExportTable
    HEADERS = [
      "Room Number", "Room Type", "Assign To", "Room Status", "Arrival Time",
      "Arrival Date", "Departure", "Nights", "Task Details", "Task Status", "Remark"
    ].freeze
    COLUMN_TYPES = %i[text text text text text date date integer text text text].freeze
    PDF_HEADERS = [ "Room", "Room Type", "Assigned To", "Room Status", "Stay", "Task Details", "Task Status", "Remark" ].freeze
    PDF_COLUMN_WIDTHS = [ 55, 90, 85, 70, 120, 190, 85, 82 ].freeze

    attr_reader :rows

    def initialize(room_groups:)
      @rows = build_rows(room_groups)
    end

    def task_count = rows.size
    def assigned_count = rows.count { |row| row[2] != "Unassigned" }

    def pdf_rows
      rows.map do |row|
        [ row[0], row[1], row[2], row[3], stay_label(row), row[8], row[9], row[10].presence || "-" ]
      end
    end

    private

    # This is a report of tasks, down to its counts and its "no tasks found"
    # message, so the board's placeholder rows for rooms with nothing to do are
    # left out rather than printed as work and counted as work.
    def build_rows(room_groups)
      room_groups.flat_map do |group|
        group[:rooms].flat_map do |room|
          room[:hk_requests].reject(&:placeholder?).map { |request| row_for(group, room, request) }
        end
      end
    end

    def row_for(group, room, request)
      booking = room[:active_booking]
      [
        room[:room_number].to_s,
        group[:room_type].name.to_s,
        request.assigned_to_name,
        ::Rooms::StatusPresentation.label(room[:resolved_status]),
        booking&.checked_in_at&.strftime("%I:%M %p") || "-",
        booking&.check_in&.to_date,
        booking&.check_out&.to_date,
        booking&.duration_in_nights,
        request.request_details.to_s,
        # The same status the board shows: a checkout request carries its own
        # lifecycle, and the report must not name it something else.
        request.display_status.to_s.humanize.titleize,
        ""
      ]
    end

    def stay_label(row)
      return "-" unless row[5] && row[6]

      "#{row[5].strftime('%d %b')} - #{row[6].strftime('%d %b')} (#{row[7]} nights)"
    end
  end
end
