# frozen_string_literal: true

module Rooms
  # The room directory for a hotel, read from the `rooms` table.
  #
  # This is the single answer to "which rooms exist". Housekeeping, Stay View,
  # availability, and every room-number guard read it, so the physical-room
  # record stays the source of truth and `room_types.room_numbers` stays a
  # compatibility copy.
  #
  # Rooms carry `position`, the index of the room inside its category. Ordering
  # by it reproduces the order of the legacy JSON list.
  class DirectoryQuery
    EMPTY = [].freeze

    Row = Data.define(:room_type_id, :number, :position, :room_group_id, :room_group_name) do
      def initialize(room_type_id:, number:, position:, room_group_id: nil, room_group_name: nil)
        super(
          room_type_id:,
          number: number.to_s.freeze,
          position: position.to_i,
          room_group_id:,
          room_group_name: room_group_name&.to_s&.freeze
        )
      end
    end

    Result = Data.define(:rows, :numbers_by_room_type, :keys) do
      def numbers_for(room_type_id)
        numbers_by_room_type.fetch(room_type_id, EMPTY)
      end

      def include?(room_type_id, number)
        keys.include?([ room_type_id, number.to_s ])
      end

      def any?(room_type_id) = numbers_for(room_type_id).any?
    end

    # The directory of one room category. Room-number guards hold a room type
    # rather than a hotel, so they read this narrower view.
    RoomTypeDirectory = Data.define(:numbers) do
      def initialize(numbers:)
        super(numbers: numbers.map { |number| number.to_s.freeze }.freeze)
      end

      def include?(number) = numbers.include?(number.to_s)
      def any? = numbers.any?
    end

    def self.call(...) = new(...).call

    def self.for_room_type(room_type)
      return RoomTypeDirectory.new(numbers: EMPTY) if room_type.blank? || !room_type.persisted?

      RoomTypeDirectory.new(
        numbers: Room.where(room_type_id: room_type.id).active.order(:position, :id).pluck(:number)
      )
    end

    def initialize(hotel:)
      @hotel = hotel
    end

    def call
      rows = load_rows
      Result.new(
        rows: rows.freeze,
        numbers_by_room_type: numbers_by_room_type(rows),
        keys: rows.map { |row| [ row.room_type_id, row.number ] }.to_set.freeze
      )
    end

    private

    attr_reader :hotel

    def load_rows
      hotel.rooms.active
        .left_joins(:room_group)
        .order(:room_type_id, :position, :id)
        .pluck(:room_type_id, :number, :position, :room_group_id, "room_groups.name")
        .map { |values| Row.new(**%i[room_type_id number position room_group_id room_group_name].zip(values).to_h) }
    end

    def numbers_by_room_type(rows)
      rows.group_by(&:room_type_id)
        .transform_values { |grouped| grouped.map(&:number).freeze }
        .freeze
    end
  end
end
