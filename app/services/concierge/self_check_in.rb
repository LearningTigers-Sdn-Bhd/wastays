module Concierge
  class SelfCheckIn
    def initialize(booking:)
      @booking = booking
      @hotel = booking.hotel
      @policy = @hotel.property_policy
    end

    def call
      return build_failure(:wrong_date) unless on_check_in_date?
      return build_failure(:too_early)  if too_early?

      room_type = @booking.booking_rooms.first&.room_type
      return build_failure(:no_room_available) unless room_type

      room_number = nil
      error_message = nil
      no_room = false

      # Lock the room_type row so concurrent self check-ins serialize and
      # cannot both pick the same available room number.
      room_type.with_lock do
        room_number = find_available_room
        if room_number.nil?
          no_room = true
          next
        end

        assign = Bookings::AssignRoom.new(booking: @booking, room_number: room_number, user: nil).call
        unless assign.success?
          error_message = assign.error
          raise ActiveRecord::Rollback
        end

        transition = Bookings::TransitionStatus.new(booking: @booking, status: "checked_in").call
        unless transition.success?
          error_message = transition.error
          raise ActiveRecord::Rollback
        end
      end

      return build_failure(:no_room_available) if no_room
      return build_failure(:error, message: error_message) if error_message.present?

      Result.success(booking: @booking, room_number: room_number)
    rescue StandardError => e
      Result.failure(error_code: :error, message: e.message)
    end

    private

    def on_check_in_date?
      hotel_now.to_date >= @booking.check_in.to_date
    end

    def too_early?
      return false if @policy&.check_in_time.blank?
      return false if hotel_now.to_date > @booking.check_in.to_date

      hotel_now < @booking.check_in.in_time_zone(@hotel.hotel_time_zone)
    end

    def hotel_now
      @hotel_now ||= Time.current.in_time_zone(@hotel.hotel_time_zone)
    end

    def find_available_room
      room_type = @booking.booking_rooms.first&.room_type
      return nil unless room_type

      available = Bookings::AvailableRoomNumbers.new(
        hotel: @hotel,
        room_type: room_type,
        check_in: @booking.check_in.to_date,
        check_out: @booking.check_out.to_date,
        exclude_booking_id: @booking.id
      ).call

      available.min_by { |room_number| [ room_number.to_i, room_number ] }
    end

    def build_failure(code, message: nil)
      Result.failure(error_code: code, message: message)
    end
  end
end
