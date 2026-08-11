# frozen_string_literal: true

module HotelPortal
  module RoomGroups
    class Save
      Result = Data.define(:room_group) do
        def success? = room_group.errors.empty?
      end

      def self.call(...) = new(...).call

      def initialize(hotel:, attributes:, room_group: nil)
        @hotel = hotel
        @room_group = room_group || hotel.room_groups.build
        @name = attributes[:name]
      end

      def call
        room_group.name = name
        room_group.save
        Result.new(room_group: room_group)
      end

      private

      attr_reader :hotel, :room_group, :name
    end
  end
end
