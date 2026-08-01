# frozen_string_literal: true

module HousekeepingTasks
  class UpdateRoomStatus < RoomOperation
    def initialize(hotel:, room_type_id:, room_number:, date:, status:, notes:, current_user:, now: Time.current)
      @hotel = hotel
      @room_type_id = room_type_id
      @room_number = room_number
      @date = date
      @status = status.to_s
      @notes = notes
      @current_user = current_user
      @now = now
    end

    def call
      authorize_housekeeping!
      ensure_current_business_date!

      booking = late_checkout_booking if @status == "late_checkout_detected"
      reason = @notes.presence || room_status.notes

      Rooms::SetStatus.new(
        room_status: room_status,
        status: @status,
        user: @current_user,
        reason: reason,
        booking: booking,
        clear_assignment: @status == "ready"
      ).call
    rescue ActiveRecord::RecordNotFound
      raise
    rescue Pundit::NotAuthorizedError
      raise
    rescue StandardError => e
      failure(e.message)
    end

    private

    def late_checkout_booking
      booking = @hotel.bookings
        .where(status: "checked_in", checked_out_at: nil)
        .joins(:booking_rooms)
        .find_by(
          booking_rooms: {
            room_type_id: room_status.room_type_id,
            room_number: room_status.room_number
          }
        )

      raise ArgumentError, "Late checkout requires a checked-in booking in this room." unless booking
      raise ArgumentError, "Late checkout can only be reported after the scheduled checkout time." if @now < booking.check_out

      booking
    end
  end
end
