# frozen_string_literal: true

module StayView
  class CalculateCounts
    def self.call(room_groups:)
      rows = room_groups.flat_map(&:rooms)
      StatusCounts.new(
        rooms: rows.size,
        physical_statuses: tally(rows.filter_map(&:current_physical_status)),
        occupancies: tally(rows.flat_map(&:day_cells).flat_map(&:occupancies).map(&:state)),
        booking_statuses: tally(rows.flat_map(&:booking_segments).map(&:status)),
        operational_segments: tally(rows.flat_map(&:operational_segments).map(&:kind))
      )
    end

    def self.tally(values)
      values.tally.sort.to_h
    end

    private_class_method :tally
  end
end
