module AiConciergeV3
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
                "date_range" => date_range(booking),
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
                            .where(status: %w[checked_in confirmed])
                            .order(Arel.sql("CASE WHEN status = 'checked_in' THEN 0 ELSE 1 END"))
                            .order(check_in: :asc)
        end

        def date_range(booking)
          [ booking.check_in, booking.check_out ].map { |date| format_date(date) }.join(" - ")
        end

        def room_type_name_for(booking)
          room = booking.booking_rooms.first
          room&.room_type&.name.presence || room&.room_type_snapshot&.dig("name").presence || "Room not assigned"
        end

        def format_date(value)
          return value.to_s if value.blank?

          date = value.is_a?(Date) ? value : Date.parse(value.to_s)
          date.strftime("%B %-d")
        rescue Date::Error
          value.to_s
        end
      end
    end
  end
end
