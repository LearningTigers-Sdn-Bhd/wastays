# frozen_string_literal: true

module ChannelManagers
  module Financials
    class AllocateGroupSnapshot
      def self.call(bookings:, rooms:)
        available = bookings.reject { |booking| booking.status == "cancelled" }
          .sort_by { |booking| [ booking.group_position || Float::INFINITY, booking.id ] }
        Array(rooms).flat_map.with_index do |room, room_index|
          Array.new([ room[:quantity].to_i, 1 ].max).map.with_index do |_unused, unit_index|
            booking = available.find { |candidate| matches?(candidate, room) } || available.first
            raise ArgumentError, "Financial room cannot be allocated to a booking" unless booking
            available.delete(booking)
            { booking:, booking_room: booking.booking_rooms.first!, room:, room_index:, unit_index: }
          end
        end
      end

      def self.matches?(booking, room)
        candidate = booking.booking_rooms.first
        candidate && candidate.room_type_id == room[:room_type]&.id && candidate.rate_plan_id == room[:rate_plan]&.id
      end
      private_class_method :matches?
    end
  end
end
