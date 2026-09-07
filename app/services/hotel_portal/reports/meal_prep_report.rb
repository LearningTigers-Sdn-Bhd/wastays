# frozen_string_literal: true

module HotelPortal
  module Reports
    # Meal counts are derived, never recorded: what a guest eats follows from the
    # slot their boat is on. Each slot carries its own entitlements, set per
    # property in Settings, so nothing here assumes a service time.
    class MealPrepReport
      MEALS = %w[breakfast lunch dinner].freeze

      Result = Struct.new(
        :start_date,
        :end_date,
        :records,
        :total_pax,
        :meal_type,
        keyword_init: true
      ) do
        # Every row already carries its full meal list, so narrowing to one meal
        # tab is an in-memory filter. Re-running the query per tab used to make
        # a single page load hit the database three times.
        def for_meal(meal)
          return self if meal.blank?

          filtered = records
            .select { |row| serves?(row, meal) }
            .map { |row| row.merge(meal_type: meal.to_s.titleize) }

          Result.new(
            start_date: start_date,
            end_date: end_date,
            records: filtered,
            total_pax: filtered.sum { |row| row[:pax] },
            meal_type: meal
          )
        end

        def pax_for(meal)
          rows_for(meal).sum { |row| row[:pax] }
        end

        # One section per meal being served: the "all" tab shows three, a single
        # meal tab shows its own. Every surface (screen, sheets, PDF pages) lays
        # itself out from these.
        def sections
          (meal_type.presence ? [ meal_type ] : MEALS).map do |meal|
            rows = rows_for(meal)
            { title: meal.to_s.titleize, meal: meal.to_s, rows: rows, total_pax: rows.sum { |row| row[:pax] } }
          end
        end

        def rows_for(meal)
          records.select { |row| serves?(row, meal) }
        end

        private

        def serves?(row, meal)
          row[:meals].any? { |served| served.casecmp?(meal.to_s) }
        end
      end

      def initialize(hotel:, start_date:, end_date:, meal_type: nil)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @meal_type = meal_type.presence
      end

      def call
        @meal_type ? full_result.for_meal(@meal_type) : full_result
      end

      private

      def full_result
        @full_result ||= begin
          records = (rows_for(:boat_in_at, "Boat-in") + rows_for(:boat_out_at, "Boat-out"))
            .sort_by { |row| [ row[:boat_time], row[:confirmation_token] ] }

          Result.new(
            start_date: @start_date,
            end_date: @end_date,
            records: records,
            total_pax: records.sum { |row| row[:pax] },
            meal_type: nil
          )
        end
      end

      def rows_for(column, transfer_type)
        guests = booking_guests_scope.where(column => window)
        one_per_booking(guests).map { |bg| build_row(bg, bg.public_send(column), transfer_type) }
      end

      def window
        ::Boats::Schedule.day_range(hotel: @hotel, from: @start_date, to: @end_date)
      end

      # Pax counts the whole booking, so a booking must contribute one row per
      # transfer. A second guest on the same booking carrying a boat time would
      # otherwise count everyone twice.
      def one_per_booking(guests)
        guests.sort_by { |bg| [ bg.primary? ? 0 : 1, bg.id ] }.uniq(&:booking_id)
      end

      def booking_guests_scope
        BookingGuest.joins(:booking)
                    .where(bookings: { hotel_id: @hotel.id })
                    .includes(booking: { booking_rooms: :room_type }, guest: {})
      end

      def schedule
        @schedule ||= ::Boats::Schedule.new(@hotel)
      end

      # Straight off the slot the guest is booked on -- archived slots resolve
      # too, so retiring one never rewrites what was already served.
      def meals_for(time, transfer_type)
        kind = transfer_type == "Boat-in" ? "boat_in" : "boat_out"
        schedule.meals_for(time, kind).map { |meal| meal.to_s.titleize }
      end

      def build_row(bg, time, transfer_type)
        booking = bg.booking
        meals = meals_for(time, transfer_type)
        {
          guest_name: bg.name_snapshot || bg.guest.name,
          confirmation_token: booking.confirmation_token,
          type: transfer_type,
          pax: booking.adults.to_i + booking.children.to_i,
          room_type: booking.booking_rooms.map { |br| br.room_type&.name }.compact.uniq.join(", ").presence || "—",
          room_number: booking.booking_rooms.map(&:room_number).compact.join(", ").presence || "—",
          boat_time: time,
          transfer_date: format_transfer_date(time),
          formatted_boat_time: format_boat_time(time),
          meals: meals,
          meal_type: meals.join(", "),
          total_amount: booking.total_amount,
          currency: booking.currency
        }
      end

      def format_boat_time(value)
        return "—" if value.blank?

        value.in_time_zone(@hotel.hotel_time_zone).strftime("%I:%M %p")
      end

      def format_transfer_date(value)
        return "—" if value.blank?

        value.in_time_zone(@hotel.hotel_time_zone).strftime("%d %b %Y")
      end
    end
  end
end
