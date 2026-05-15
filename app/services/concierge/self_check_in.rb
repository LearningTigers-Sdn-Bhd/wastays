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

      room_number = find_available_room
      return build_failure(:no_room_available) unless room_number

      error_message = nil

      ActiveRecord::Base.transaction do
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

      return build_failure(:error, message: error_message) if error_message.present?

      Result.success(booking: @booking, room_number: room_number)
    rescue StandardError => e
      Result.failure(error_code: :error, message: e.message)
    end

    private

    def on_check_in_date?
      Time.zone.today >= @booking.check_in.to_date
    end

    def too_early?
      return false if @policy&.check_in_time.blank?
      return false if Time.zone.today > @booking.check_in.to_date

      check_in_dt = Time.zone.parse("#{Time.zone.today} #{@policy.check_in_time}")
      return false unless check_in_dt

      Time.current < check_in_dt
    rescue ArgumentError, TypeError
      false
    end

    def find_available_room
      room_type = @booking.booking_rooms.first&.room_type
      return nil unless room_type

      inventory = RoomInventory.find_by(room_type: room_type, date: Time.zone.today)
      return nil unless inventory

      candidates = inventory.available_room_numbers
      return nil if candidates.blank?

      occupied = RoomStatus.where(hotel: @hotel, room_type: room_type, room_number: candidates)
                           .where.not(status: RoomStatus::ASSIGNABLE_STATUSES)
                           .pluck(:room_number)

      (candidates - occupied).first
    end

    def build_failure(code, message: nil)
      Result.failure(error_code: code, message: message)
    end
  end
end
