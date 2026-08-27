# frozen_string_literal: true

module Rooms
  class NumberingContext
    Result = Data.define(:reserved_numbers, :suggested_start)

    def self.call(...) = new(...).call

    def initialize(hotel:, room_type: nil)
      @hotel = hotel
      @room_type = room_type
    end

    def call
      Result.new(
        reserved_numbers: reserved_numbers.freeze,
        suggested_start: numeric_numbers.max.to_i.then { |number| number.positive? ? number + 1 : 101 }
      )
    end

    private

    attr_reader :hotel, :room_type

    def reserved_numbers
      @reserved_numbers ||= (json_numbers + physical_room_numbers)
        .map { |number| number.to_s.strip }
        .reject(&:blank?)
        .uniq
        .sort
    end

    def json_numbers
      scope = hotel.room_types
      scope = scope.where.not(id: room_type.id) if room_type&.persisted?
      scope.pluck(:room_numbers).flat_map { |numbers| Array(numbers).flatten }
    end

    def physical_room_numbers
      return [] unless Room.table_exists?

      scope = hotel.rooms
      scope = scope.where.not(room_type_id: room_type.id) if room_type&.persisted?
      scope.pluck(:number)
    end

    def numeric_numbers
      reserved_numbers.filter_map do |number|
        Integer(number, exception: false) if number.match?(/\A\d+\z/)
      end
    end
  end
end
