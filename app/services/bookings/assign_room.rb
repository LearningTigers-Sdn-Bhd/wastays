# frozen_string_literal: true

require "ostruct"

module Bookings
  class AssignRoom
    def initialize(booking:, room_number:, user:, override: false, override_reason: nil)
      @booking = booking
      @room_number = room_number.to_s.strip
      @user = user
      @override = ActiveModel::Type::Boolean.new.cast(override)
      @override_reason = override_reason.to_s.strip
    end

    def call
      return failure("Room number is required.") if @room_number.blank?
      return failure(blocked_message) if blocked_without_valid_override?

      BookingRoom.transaction do
        previous_room_number = booking_room.room_number
        booking_room.update!(room_number: @room_number)
        ::Bookings::RecordAuditLog.call!(
          auditable: booking_room,
          user: @user,
          action_type: "room_assignment",
          old_value: { "room_number" => previous_room_number },
          new_value: { "room_number" => @room_number },
          reason: @override_reason.presence,
          metadata: { "room_number" => @room_number, "override" => override_assignment? }
        )
        write_override_audit_log if override_assignment?
        RoomLock.where(hotel: @booking.hotel, user: @user, room_number: @room_number).destroy_all
      end

      success
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    end

    private

    def booking_room
      @booking_room ||= @booking.booking_rooms.first || @booking.booking_rooms.build(
        room_type: room_type,
        quantity: 1,
        subtotal: @booking.total_amount
      )
    end

    def room_type
      @room_type ||= @booking.booking_rooms.first&.room_type
    end

    def room_status
      @room_status ||= RoomStatus.find_or_create_by!(
        hotel: @booking.hotel,
        room_type: room_type,
        room_number: @room_number
      )
    end

    def blocked_without_valid_override?
      return false if room_status.assignable?
      return false if override_assignment?

      true
    end

    def override_assignment?
      @override &&
        @override_reason.present? &&
        @user.has_permission?("override_room_status_assignment", hotel: @booking.hotel)
    end

    def blocked_message
      "Room #{@room_number} is #{room_status.status.humanize.titleize} and cannot be assigned until it is ready."
    end

    def write_override_audit_log
      RoomOperationalAuditLog.create!(
        hotel: @booking.hotel,
        room_type: room_type,
        booking: @booking,
        user: @user,
        room_number: @room_number,
        event_type: "assignment_override",
        old_status: room_status.status,
        new_status: room_status.status,
        reason: @override_reason,
        metadata: { "booking_id" => @booking.id }
      )
    end

    def success
      OpenStruct.new(success?: true, booking: @booking)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
