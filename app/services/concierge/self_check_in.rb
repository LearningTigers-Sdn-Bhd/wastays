module Concierge
  class SelfCheckIn
    def initialize(booking:, latitude: nil, longitude: nil)
      @booking = booking
      @hotel = booking.hotel
      @policy = @hotel.property_policy
      @latitude = latitude.to_f if latitude.present?
      @longitude = longitude.to_f if longitude.present?
    end

    def call
      return build_failure(:wrong_date) unless on_check_in_date?
      return build_failure(:too_early)  if too_early?
      return build_failure(:closed_check_in_date) if @hotel.date_closed?(@booking.check_in)

      if location_check_enabled?
        return build_failure(:missing_location) if location_missing?
        return build_failure(:too_far_away) if too_far?
      end

      room_type = @booking.booking_rooms.first&.room_type
      return build_failure(:no_room_available) unless room_type

      room_number = nil
      error_message = nil
      closed_check_in_date = false
      no_room = false

      # Lock the room_type row so concurrent self check-ins serialize and
      # cannot both pick the same available room number.
      room_type.with_lock do
        room_number = find_available_room
        if room_number.nil?
          no_room = true
          next
        end

        process = Bookings::ProcessCheckIn.new(
          bookings: [ @booking ],
          details: {
            checked_in_at: hotel_now,
            room_assignments: { @booking.booking_rooms.first.id.to_s => room_number }
          },
          user: nil,
          source: "concierge_page"
        ).call
        unless process.success?
          if @hotel.date_closed?(@booking.check_in)
            closed_check_in_date = true
          else
            error_message = process.error.presence || "Check-in lifecycle failed."
          end
          raise ActiveRecord::Rollback
        end
      end

      return build_failure(:no_room_available) if no_room
      return build_failure(:closed_check_in_date) if closed_check_in_date
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

      check_in_date = @booking.check_in.to_date
      check_in_opening_time = @hotel.hotel_time_zone.parse("#{check_in_date} #{@policy.check_in_time}")
      return false unless check_in_opening_time

      hotel_now < check_in_opening_time
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

    def location_check_enabled?
      @hotel.geolocation_enabled? && @hotel.latitude.present? && @hotel.longitude.present?
    end

    def location_missing?
      @latitude.nil? || @longitude.nil?
    end

    def too_far?
      distance = calculate_distance(@latitude, @longitude, @hotel.latitude, @hotel.longitude)
      distance > 50.0
    end

    def calculate_distance(lat1, lon1, lat2, lon2)
      rad_per_deg = Math::PI / 180
      r_meters = 6_371_000 # Earth's radius in meters

      dlat_rad = (lat2 - lat1) * rad_per_deg
      dlon_rad = (lon2 - lon1) * rad_per_deg

      lat1_rad = lat1 * rad_per_deg
      lat2_rad = lat2 * rad_per_deg

      a = Math.sin(dlat_rad / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2)**2
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

      r_meters * c
    end
  end
end
