# frozen_string_literal: true

require "ostruct"

module Bookings
  # Puts a booking into the first room that is clean and free for the whole
  # stay. Reached from channel-manager ingestion, from a desk booking left
  # without a room, and from check-in as a last chance before arrival.
  class AutoAssignRoom
    ASSIGNABLE_BOOKING_STATUSES = %w[confirmed no_show_detected checked_in due_out_detected checkout_required].freeze

    def initialize(booking:, source: "channel_manager")
      @booking = booking
      @source = source
    end

    def call
      return skipped("Automatic room assignment is off for this property") unless @booking.hotel.auto_assign_rooms_enabled?

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

      # May run inside the caller's transaction, so keep every write in a
      # savepoint: a database level failure here must not abort the surrounding
      # booking write. Assignment is a convenience, never a reason to lose the
      # booking or block a check-in.
      ActiveRecord::Base.transaction(requires_new: true) do
        assign(booking_room, available_numbers.first)
      end
    rescue StandardError => e
      Rails.logger.error(
        "Automatic room assignment failed booking_id=#{@booking.id} source=#{@source} error=#{e.message.inspect}"
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
        metadata: { "automatic" => true, "source" => @source }
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
        source: @source,
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
