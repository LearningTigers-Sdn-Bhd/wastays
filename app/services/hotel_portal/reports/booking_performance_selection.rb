# frozen_string_literal: true

module HotelPortal
  module Reports
    # Builds the record selection of the booking performance table. The user
    # can select rows under one grouping and then change the grouping, so the
    # selection keeps the grouping that produced it.
    module BookingPerformanceSelection
      module_function

      def new(report:, group_by:, booking_ids:, group_values:, excluded_booking_ids:)
        grouping = group_by.to_s.presence_in(BookingPerformanceReport::GROUPINGS) || report.group_by
        table = grouping == report.group_by ? report : report.regroup(grouping)
        RecordSelection.new(
          records: report.rows,
          record_id: ->(row) { row.booking_id },
          group_key: ->(row) { table.group_key_for(row) },
          ids: booking_ids,
          group_values:,
          excluded_ids: excluded_booking_ids
        )
      end
    end
  end
end
