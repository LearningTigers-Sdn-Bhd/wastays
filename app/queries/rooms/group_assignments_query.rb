# frozen_string_literal: true

module Rooms
  # Room-group membership for a hotel, keyed the way the operational boards key
  # their rows. Housekeeping and Stay View both enumerate rooms from
  # `room_types.room_numbers` until Milestone 6, so the group is looked up
  # beside that list rather than read from it.
  class GroupAssignmentsQuery
    UNGROUPED = "__ungrouped__"
    UNGROUPED_LABEL = "Ungrouped"

    Reference = Data.define(:id, :name) do
      def initialize(id:, name:)
        super(id:, name: name.to_s.freeze)
      end
    end

    def self.call(...) = new(...).call

    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      Result.new(assignments: assignments, options: options)
    end

    private

    attr_reader :hotel

    def rows
      @rows ||= hotel.rooms.active
        .where.not(room_group_id: nil)
        .joins(:room_group)
        .order("room_groups.name", "room_groups.id")
        .pluck(:room_type_id, :number, :room_group_id, "room_groups.name")
    end

    def assignments
      rows.each_with_object({}) do |(room_type_id, number, room_group_id, name), result|
        result[[ room_type_id, number.to_s ]] = reference(room_group_id, name)
      end.freeze
    end

    def options
      rows.map { |row| reference(row[2], row[3]) }.uniq.freeze
    end

    def reference(id, name)
      @references ||= {}
      @references[id] ||= Reference.new(id:, name:)
    end

    Result = Data.define(:assignments, :options) do
      def for(room_type_id, room_number)
        assignments[[ room_type_id, room_number.to_s ]]
      end

      def id_for(room_type_id, room_number)
        self.for(room_type_id, room_number)&.id
      end

      def name_for(room_type_id, room_number)
        self.for(room_type_id, room_number)&.name || UNGROUPED_LABEL
      end
    end
  end
end
