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

      # 1. Get all room numbers defined for this category
      all_rooms = @room_type.room_numbers || []

      # 2. Find room numbers already occupied for these dates
      occupied = @hotel.bookings.where(status: [ "confirmed", "checked_in", "completed" ])
      occupied = occupied.where.not(id: @exclude_booking_id) if @exclude_booking_id

      occupied_numbers = occupied.where("check_in < ? AND check_out > ?", @check_out, @check_in)
                                 .pluck(Arel.sql("hotel_snapshot->>'room_number'"))
                                 .compact.map(&:to_s).uniq

      # 3. Filter them out
      (all_rooms - occupied_numbers).reject(&:blank?)
    end
  end
end
