# frozen_string_literal: true

require "ostruct"

module ChannelManagers
  class AutoAssignRoom
    ASSIGNABLE_BOOKING_STATUSES = %w[confirmed no_show_detected checked_in due_out_detected checkout_required].freeze

    def initialize(booking:)
      @booking = booking
    end

    def call
      booking_room = @booking.booking_rooms.first
      return skipped("Booking has no room category") unless booking_room&.room_type
      return skipped("Booking status does not hold inventory") unless @booking.status.in?(ASSIGNABLE_BOOKING_STATUSES)

      available_numbers = Bookings::AvailableRoomNumbers.new(
        hotel: @booking.hotel,
        room_type: booking_room.room_type,
        check_in: @booking.check_in,
        check_out: @booking.check_out,
        exclude_booking_id: @booking.id
      ).call

      if booking_room.room_number.present? && available_numbers.include?(booking_room.room_number.to_s)
        return success(booking_room.room_number, preserved: true)
      end

      # Runs inside the ingestion transaction, so keep every write in a savepoint:
      # a database level failure here must not abort the surrounding booking write.
      ActiveRecord::Base.transaction(requires_new: true) do
        assign(booking_room, available_numbers.first)
      end
    rescue StandardError => e
      Rails.logger.error(
        "Channel manager automatic room assignment failed booking_id=#{@booking.id} error=#{e.message.inspect}"
      )
      failure(e.message)
    end

    private

    def assign(booking_room, room_number)
      clear_invalid_assignment(booking_room) if booking_room.room_number.present?
      return skipped("No physical room is available for the full stay") if room_number.blank?

      result = Bookings::AssignRoom.new(
        booking: @booking,
        room_number: room_number,
        user: nil,
        metadata: { "automatic" => true, "source" => "channel_manager" }
      ).call

      return success(room_number) if result.success?

      failure(result.error)
    end

    def clear_invalid_assignment(booking_room)
      previous_room_number = booking_room.room_number
      booking_room.update!(room_number: nil)
      Bookings::RecordAuditLog.call!(
        auditable: booking_room,
        action_type: "room_removed",
        source: "channel_manager",
        old_value: { "room_number" => previous_room_number },
        new_value: { "room_number" => nil },
        metadata: { "automatic" => true, "reason" => "Room is no longer available for the full stay" }
      )
    end

    def success(room_number, preserved: false)
      OpenStruct.new(success?: true, assigned?: true, room_number: room_number, preserved?: preserved)
    end

    def skipped(message)
      OpenStruct.new(success?: true, assigned?: false, message: message)
    end

    def failure(message)
      OpenStruct.new(success?: false, assigned?: false, message: message)
    end
  end
end
