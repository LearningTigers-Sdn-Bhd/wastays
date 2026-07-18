# frozen_string_literal: true

module StayView
  class CalculateCounts
    RESERVED_STATUSES = %i[confirmed review_no_show].freeze
    OCCUPIED_STATUSES = %i[checked_in review_due_out checkout_required].freeze
    DUE_OUT_STATUSES = %i[review_due_out checkout_required].freeze

    def self.call(room_groups:, reference_date:, operational_date:)
      rows = room_groups.flat_map(&:rooms)
      states = {
        all: rows.size,
        occupied: count(rows) { |room| occupied?(room, reference_date) },
        reserved: count(rows) { |room| reserved?(room, reference_date) },
        blocked: count(rows) { |room| blocked?(room, reference_date) },
        due_out: count(rows) { |room| due_out?(room, reference_date, operational_date) },
        dirty: count(rows) { |room| room.current_physical_status == :dirty }
      }
      states[:vacant] = count(rows) do |room|
        !occupied?(room, reference_date) && !reserved?(room, reference_date) &&
          !blocked?(room, reference_date) && !due_out?(room, reference_date, operational_date)
      end

      StatusCounts.new(
        reference_date:,
        room_states: states
      )
    end

    # Single dominant operational status for one room on a date, using the same
    # predicates as the legend counts so the two never drift. Dirty is a physical
    # condition and is intentionally excluded here.
    def self.operational_status(room, reference_date, operational_date)
      return :blocked if blocked?(room, reference_date)
      return :due_out if due_out?(room, reference_date, operational_date)
      return :occupied if occupied?(room, reference_date)
      return :reserved if reserved?(room, reference_date)

      :vacant
    end

    def self.count(rows, &block)
      rows.count(&block)
    end

    def self.occupied?(room, date)
      active_booking_with_status?(room, date, OCCUPIED_STATUSES)
    end

    def self.reserved?(room, date)
      active_booking_with_status?(room, date, RESERVED_STATUSES)
    end

    def self.active_booking_with_status?(room, date, statuses)
      room.booking_segments.any? do |segment|
        statuses.include?(segment.status) && segment.check_in <= date && date < segment.check_out
      end
    end

    def self.blocked?(room, date)
      room.operational_segments.any? { |segment| segment.start_date <= date && date < segment.end_date }
    end

    def self.due_out?(room, date, operational_date)
      status_due_out = room.booking_segments.any? do |segment|
        DUE_OUT_STATUSES.include?(segment.status) && segment.check_out <= date
      end
      current_late_checkout = date == operational_date && room.operational_flags[:late_checkout]
      status_due_out || current_late_checkout
    end

    private_class_method :count, :occupied?, :reserved?, :active_booking_with_status?, :blocked?, :due_out?
  end
end
