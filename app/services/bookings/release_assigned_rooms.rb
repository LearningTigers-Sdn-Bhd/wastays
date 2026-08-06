# frozen_string_literal: true

require "ostruct"

module Bookings
  class ReleaseAssignedRooms
    def self.call(booking:, user:, event_type:, reason:, metadata: {})
      new(booking: booking, user: user, event_type: event_type, reason: reason, metadata: metadata).call
    end

    def initialize(booking:, user:, event_type:, reason:, metadata: {})
      @booking = booking
      @user = user
      @event_type = event_type
      @reason = reason
      @metadata = metadata.stringify_keys.merge("booking_id" => booking.id)
    end

    def call
      @booking.booking_rooms.includes(:room_type).each do |booking_room|
        next if booking_room.room_number.blank?

        room_status = RoomStatus.create_with(status: "ready").find_or_create_by!(
          hotel: @booking.hotel,
          room_type: booking_room.room_type,
          room_number: booking_room.room_number
        )
        was_ready = room_status.status == "ready"
        result = Rooms::SetStatus.new(
          room_status: room_status,
          status: "ready",
          user: @user,
          booking: @booking,
          event_type: @event_type,
          reason: @reason,
          metadata: @metadata
        ).call
        return result unless result.success?

        record_ready_release(room_status) if was_ready
      end

      OpenStruct.new(success?: true)
    end

    private

    def record_ready_release(room_status)
      RoomOperationalAuditLog.create!(
        hotel: room_status.hotel,
        room_type: room_status.room_type,
        booking: @booking,
        user: @user,
        room_number: room_status.room_number,
        event_type: @event_type,
        old_status: "ready",
        new_status: "ready",
        reason: @reason,
        metadata: @metadata
      )
    end
  end
end
