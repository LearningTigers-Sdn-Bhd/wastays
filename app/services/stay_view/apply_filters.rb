# frozen_string_literal: true

module StayView
  class ApplyFilters
    def self.call(room_groups:, filters:)
      room_groups.filter_map do |group|
        next if filters.room_type_id && filters.room_type_id != group.room_type_id

        rooms = group.rooms.filter_map { |room| filter_room(room, filters) }
        next if rooms.empty?

        RoomGroup.new(room_type_id: group.room_type_id, name: group.name, rooms: rooms)
      end.freeze
    end

    def self.filter_room(room, filters)
      filtered = filter_booking_status(room, filters.booking_status)
      return unless filtered
      return unless physical_status_matches?(filtered, filters.physical_status)
      return unless occupancy_matches?(filtered, filters.occupancy)

      filtered
    end

    def self.filter_booking_status(room, status)
      return room unless status

      segments = room.booking_segments.select { |segment| segment.status == status }
      cells = room.day_cells.map do |cell|
        occupancies = cell.occupancies.select { |entry| entry.booking_status == status }
        occupancies = [ Occupancy.new(state: :available, label: "Available") ] if occupancies.empty?
        DayCell.new(date: cell.date, occupancies:, operational_kinds: cell.operational_kinds)
      end
      room.with(booking_segments: segments.freeze, day_cells: cells.freeze) if segments.any?
    end

    def self.physical_status_matches?(room, status)
      status.nil? || room.current_physical_status == status
    end

    def self.occupancy_matches?(room, occupancy)
      occupancy.nil? || room.day_cells.any? { |cell| cell.occupancies.any? { |entry| entry.state == occupancy } }
    end

    private_class_method :filter_room, :filter_booking_status, :physical_status_matches?, :occupancy_matches?
  end
end
