# frozen_string_literal: true

module StayView
  class ApplyFilters
    def self.call(room_groups:, filters:, hotel: nil, reference_date: nil, operational_date: reference_date)
      room_groups.filter_map do |group|
        next if filters.room_type_id && filters.room_type_id != group.room_type_id

        rooms = group.rooms.filter_map do |room|
          filter_room(room, filters, hotel:, reference_date:, operational_date:)
        end
        next if rooms.empty?

        RoomGroup.new(room_type_id: group.room_type_id, name: group.name, rooms: rooms)
      end.freeze
    end

    def self.filter_room(room, filters, hotel:, reference_date:, operational_date:)
      return unless room_group_matches?(room, filters.room_group_id)
      return unless physical_status_matches?(room, filters.physical_status)
      return unless occupancy_matches?(room, filters.occupancy)
      return unless room_state_matches?(room, filters.room_state, hotel:, reference_date:, operational_date:)

      room
    end

    def self.room_group_matches?(room, room_group_id)
      return true if room_group_id.nil?
      return !room.grouped? if room_group_id == ::Rooms::GroupAssignmentsQuery::UNGROUPED

      room.room_group_id == room_group_id
    end

    def self.physical_status_matches?(room, status)
      status.nil? || room.current_physical_status == status
    end

    def self.occupancy_matches?(room, occupancy)
      occupancy.nil? || room.day_cells.any? { |cell| cell.occupancies.any? { |entry| entry.state == occupancy } }
    end

    def self.room_state_matches?(room, room_state, hotel:, reference_date:, operational_date:)
      return true unless room_state

      ResolveRoomCardSlots.call(
        hotel:,
        room:,
        date: reference_date,
        operational_date:,
        log_conflicts: false
      ).state == room_state
    end

    private_class_method :filter_room, :physical_status_matches?, :occupancy_matches?,
      :room_state_matches?, :room_group_matches?
  end
end
