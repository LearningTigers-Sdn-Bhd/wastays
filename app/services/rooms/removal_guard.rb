# frozen_string_literal: true

module Rooms
  class RemovalGuard
    Result = ApplicationResult.define(:room, :reasons)

    REASON_LABELS = {
      assigned_booking: "an active booking",
      room_block: "a current or future room block",
      room_lock: "an active room lock",
      housekeeping_task: "an open housekeeping task"
    }.freeze

    def self.call(room:)
      new(room:).call
    end

    def initialize(room:)
      @room = room
    end

    def call
      reasons = blocking_reasons
      return Result.success(room: @room, reasons: []) if reasons.empty?

      Result.failure(error_message(reasons), room: @room, reasons: reasons)
    end

    private

    def blocking_reasons
      [].tap do |reasons|
        reasons << :assigned_booking if assigned_booking?
        reasons << :room_block if current_or_future_block?
        reasons << :room_lock if active_room_lock?
        reasons << :housekeeping_task if open_housekeeping_task?
      end
    end

    def assigned_booking?
      BookingRoom.joins(:booking)
        .where(room_type_id: @room.room_type_id, room_number: @room.number)
        .where(bookings: { hotel_id: @room.hotel_id })
        .where.not(bookings: { status: Bookings::StatusLifecycle::TERMINAL_STATUSES })
        .exists?
    end

    def current_or_future_block?
      RoomBlock.where(
        hotel_id: @room.hotel_id,
        room_type_id: @room.room_type_id,
        room_number: @room.number,
        completed_at: nil
      ).where("end_date IS NULL OR end_date >= ?", business_date).exists?
    end

    def active_room_lock?
      RoomLock.active.exists?(
        hotel_id: @room.hotel_id,
        room_type_id: @room.room_type_id,
        room_number: @room.number
      )
    end

    def open_housekeeping_task?
      HousekeepingRequest.in_hotel(@room.hotel)
        .open_tasks
        .left_joins(booking: :booking_rooms)
        .where(housekeeping_room_match, room_number: @room.number, room_type_id: @room.room_type_id)
        .exists?
    end

    def housekeeping_room_match
      <<~SQL.squish
        (housekeeping_requests.room_number = :room_number
          AND (housekeeping_requests.room_type_id IS NULL
            OR housekeeping_requests.room_type_id = :room_type_id))
        OR
        (housekeeping_requests.room_number IS NULL
          AND booking_rooms.room_number = :room_number
          AND COALESCE(housekeeping_requests.room_type_id, booking_rooms.room_type_id) = :room_type_id)
      SQL
    end

    def business_date
      @room.hotel.current_business_date || @room.hotel.business_date_for(Time.current)
    end

    def error_message(reasons)
      labels = reasons.map { |reason| REASON_LABELS.fetch(reason) }
      "Room #{@room.number} cannot be removed because it has #{labels.to_sentence}."
    end
  end
end
