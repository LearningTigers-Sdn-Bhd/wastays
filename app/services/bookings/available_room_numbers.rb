# frozen_string_literal: true

module Bookings
  class AvailableRoomNumbers
    def initialize(hotel:, room_type:, check_in:, check_out:, exclude_booking_id: nil)
      @hotel = hotel
      @room_type = room_type
      @check_in = check_in
      @check_out = check_out
      @exclude_booking_id = exclude_booking_id
    end

    def call
      return [] unless @room_type

      # 1. Get room numbers allowed by inventory for these dates
      inventory_allowed_rooms = (@check_in..(@check_out - 1.day)).map do |date|
        inv = @room_type.room_inventories.find_by(date: date)
        if inv
          inv.status == "open" ? inv.available_room_numbers : []
        else
          @room_type.room_numbers
        end
      end

      # Intersection of all days (must be available every day of stay)
      allowed_rooms = inventory_allowed_rooms.reduce(:&) || []

      # 2. Find room numbers already occupied for these dates by other bookings
      occupied = @hotel.bookings.where(status: [ "confirmed", "checked_in", "completed" ])
      occupied = occupied.where.not(id: @exclude_booking_id) if @exclude_booking_id

      occupied_numbers = occupied.where("check_in < ? AND check_out > ?", @check_out, @check_in)
                                 .pluck(Arel.sql("hotel_snapshot->>'room_number'"))
                                 .compact.map(&:to_s).uniq

      # 3. Filter them out
      (allowed_rooms - occupied_numbers).reject(&:blank?)
    end
  end
end
