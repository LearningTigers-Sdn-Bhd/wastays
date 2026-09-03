# frozen_string_literal: true

require "ostruct"

module HousekeepingTasks
  class RestoreLateCheckoutRoomStatuses
    def initialize(booking:, user:)
      @booking = booking
      @user = user
    end

    def call
      @booking.booking_rooms.includes(:room_type).where.not(room_number: [ nil, "" ]).find_each do |booking_room|
        restore_room(booking_room)
      end

      OpenStruct.new(success?: true, error: nil)
    rescue StandardError => e
      OpenStruct.new(success?: false, error: e.message)
    end

    private

    def restore_room(booking_room)
      room_status = RoomStatus.find_by(
        hotel: @booking.hotel,
        room_type: booking_room.room_type,
        room_number: booking_room.room_number
      )
      return unless room_status&.status == "late_checkout_detected"

      detection = RoomOperationalAuditLog
        .where(
          hotel: @booking.hotel,
          room_type: booking_room.room_type,
          booking: @booking,
          room_number: booking_room.room_number,
          event_type: "room_status_changed",
          new_status: "late_checkout_detected"
        )
        .order(created_at: :desc, id: :desc)
        .first
      return unless detection&.old_status.in?(RoomStatus::STATUSES - [ "late_checkout_detected" ])

      result = Rooms::SetStatus.new(
        room_status: room_status,
        status: detection.old_status,
        user: @user,
        booking: @booking,
        metadata: {
          "source" => "late_checkout_resolution",
          "detection_audit_log_id" => detection.id
        }
      ).call
      raise result.error unless result.success?
    end
  end
end
