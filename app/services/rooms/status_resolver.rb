# frozen_string_literal: true

require "ostruct"

module Rooms
  class StatusResolver
    def initialize(hotel:, room_type:, room_number:, date:)
      @hotel = hotel
      @room_type = room_type
      @room_number = room_number.to_s
      @date = date
    end

    def call
      return OpenStruct.new(status: "occupied", assignable: false, room_status: persisted_status) if occupied?

      status = persisted_status&.status || "ready"
      OpenStruct.new(status: status, assignable: status == "ready", room_status: persisted_status)
    end

    private

    def occupied?
      @hotel.bookings.checked_in
        .joins(:booking_rooms)
        .where("bookings.check_in <= ? AND bookings.check_out > ?", @date, @date)
        .where(booking_rooms: { room_type_id: @room_type.id, room_number: @room_number })
        .exists?
    end

    def persisted_status
      @persisted_status ||= @hotel.room_statuses.find_by(room_type_id: @room_type.id, room_number: @room_number)
    end
  end
end
