# frozen_string_literal: true

module Rooms
  # Room-group membership for a hotel, keyed the way the operational boards key
  # their rows. It reads the rows DirectoryQuery already loads, so the boards
  # ask the `rooms` table once for both the room list and its groups.
  class GroupAssignmentsQuery
    UNGROUPED = "__ungrouped__"
    UNGROUPED_LABEL = "Ungrouped"

    Reference = Data.define(:id, :name) do
      def initialize(id:, name:)
        super(id:, name: name.to_s.freeze)
      end
    end

    def self.call(...) = new(...).call

    # `directory` lets a caller that already loaded the directory reuse it
    # instead of reading the same rows twice.
    def initialize(hotel:, directory: nil)
      @hotel = hotel
      @directory_rows = directory
    end

    def call
      Result.new(assignments: assignments, options: options)
    end

    private

    attr_reader :hotel

    def rows
      @rows ||= directory.rows.select { |row| row.room_group_id.present? }
    end

    def directory
      @directory ||= @directory_rows || DirectoryQuery.call(hotel:)
    end

    def assignments
      rows.each_with_object({}) do |row, result|
        result[[ row.room_type_id, row.number ]] = reference(row.room_group_id, row.room_group_name)
      end.freeze
    end

    def options
      rows.sort_by { |row| [ row.room_group_name.to_s, row.room_group_id ] }
        .map { |row| reference(row.room_group_id, row.room_group_name) }
        .uniq
        .freeze
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
