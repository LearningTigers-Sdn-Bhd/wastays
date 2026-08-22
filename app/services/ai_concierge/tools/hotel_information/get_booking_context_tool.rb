module AiConcierge
  module Tools
    module HotelInformation
      class GetBookingContextTool
        def initialize(hotel:, phone:)
          @hotel = hotel
          @phone = phone
        end

        def call
          {
            "bookings" => bookings.map do |booking|
              {
                "check_in" => booking.check_in&.to_date,
                "check_out" => booking.check_out&.to_date,
                "room_type_name" => room_type_name_for(booking)
              }
            end
          }
        end

        private

        attr_reader :hotel, :phone

        def bookings
          @bookings ||= hotel.bookings.includes(booking_rooms: :room_type)
                            .lookup_by_phone(phone)
                            .where(status: %w[checked_in confirmed no_show_detected])
                            .order(Arel.sql("CASE WHEN status = 'checked_in' THEN 0 ELSE 1 END"))
                            .order(check_in: :asc)
        end

        def room_type_name_for(booking)
          room = booking.booking_rooms.first
          room&.room_type&.name.presence || room&.room_type_snapshot&.dig("name").presence || "Room not assigned"
        end
      end
    end
  end
end
