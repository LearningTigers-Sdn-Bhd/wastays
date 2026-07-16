# frozen_string_literal: true

module HotelPortal
  module Reports
    class MealPrepReport
      Result = Struct.new(
        :start_date,
        :end_date,
        :records,
        :total_pax,
        :meal_type,
        keyword_init: true
      )

      def initialize(hotel:, start_date:, end_date:, meal_type: nil)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @meal_type = meal_type.presence
      end

      def call
        raw_records = []

        # Boat-ins
        booking_guests_scope
          .where(boat_in_at: @start_date.beginning_of_day..@end_date.end_of_day)
          .each do |bg|
            meals = meal_types_for(bg.boat_in_at, "Boat-in")
            next if @meal_type && meals.none? { |m| m.casecmp?(@meal_type) }

            display_meals = if @meal_type
              meals.select { |m| m.casecmp?(@meal_type) }
            else
              meals
            end

            raw_records << format_row(bg, bg.boat_in_at, "Boat-in", display_meals.join(", "))
          end

        # Boat-outs
        booking_guests_scope
          .where(boat_out_at: @start_date.beginning_of_day..@end_date.end_of_day)
          .each do |bg|
            meals = meal_types_for(bg.boat_out_at, "Boat-out")
            next if @meal_type && meals.none? { |m| m.casecmp?(@meal_type) }

            display_meals = if @meal_type
              meals.select { |m| m.casecmp?(@meal_type) }
            else
              meals
            end

            raw_records << format_row(bg, bg.boat_out_at, "Boat-out", display_meals.join(", "))
          end

        # Sort by boat time
        raw_records.sort_by! { |r| r[:boat_time] }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          records: raw_records,
          total_pax: raw_records.sum { |r| r[:pax] },
          meal_type: @meal_type
        )
      end

      private

      def booking_guests_scope
        BookingGuest.joins(:booking)
                    .where(bookings: { hotel_id: @hotel.id })
                    .includes(booking: { booking_rooms: :room_type }, guest: {})
      end

      def meal_types_for(time, transfer_type)
        return [ "—" ] if time.nil?

        hour = time.in_time_zone(@hotel.hotel_time_zone).hour
        meals = []

        if transfer_type == "Boat-in"
          # Arrival Day Meals:
          # Before 12:00 PM: Breakfast, Lunch, Dinner
          # 12:00 PM - 4:59 PM: Lunch, Dinner
          # 5:00 PM onwards: Dinner
          if hour < 12
            meals << "Breakfast"
            meals << "Lunch"
            meals << "Dinner"
          elsif hour < 17
            meals << "Lunch"
            meals << "Dinner"
          else
            meals << "Dinner"
          end
        else # "Boat-out"
          # Departure Day Meals:
          # Before 12:00 PM: Breakfast
          # 12:00 PM - 4:59 PM: Breakfast, Lunch
          # 5:00 PM onwards: Breakfast, Lunch, Dinner
          if hour < 12
            meals << "Breakfast"
          elsif hour < 17
            meals << "Breakfast"
            meals << "Lunch"
          else
            meals << "Breakfast"
            meals << "Lunch"
            meals << "Dinner"
          end
        end

        meals
      end

      def format_row(bg, time, type, meal)
        booking = bg.booking
        pax_count = booking.adults.to_i + booking.children.to_i
        {
          guest_name: bg.name_snapshot || bg.guest.name,
          confirmation_token: booking.confirmation_token,
          type: type,
          pax: pax_count,
          room_type: booking.booking_rooms.map { |br| br.room_type&.name }.compact.uniq.join(", ").presence || "—",
          room_number: booking.booking_rooms.map(&:room_number).compact.join(", ").presence || "—",
          boat_time: time,
          formatted_boat_time: format_boat_time(time),
          meal_type: meal,
          total_amount: booking.total_amount,
          currency: booking.currency
        }
      end

      def format_boat_time(value)
        return "—" if value.blank?

        time_zone = @hotel.hotel_time_zone.presence || Time.zone.name
        value.in_time_zone(time_zone).strftime("%I:%M %p")
      end
    end
  end
end
