# frozen_string_literal: true

module HotelPortal
  module Reports
    class BiboReport
      # Each direction is one section, carrying only the date and time of its own
      # leg. Shared by the on-screen tables and the PDF export so both match.
      LEGS = [
        { title: "Boat-ins", rows_key: :boat_ins, date_header: "Arrival Date", date_key: :arrival_date,
          time_header: "Arrival Time", empty_message: "No boat-in records found for this selected period." },
        { title: "Boat-outs", rows_key: :boat_outs, date_header: "Departure Date", date_key: :departure_date,
          time_header: "Departure Time", empty_message: "No boat-out records found for this selected period." }
      ].freeze

      Result = Struct.new(
        :start_date,
        :end_date,
        :boat_ins,
        :boat_outs,
        :boat_in_count,
        :boat_out_count,
        keyword_init: true
      )

      def initialize(hotel:, start_date:, end_date:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def call
        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          boat_ins: boat_ins,
          boat_outs: boat_outs,
          boat_in_count: boat_ins.size,
          boat_out_count: boat_outs.size
        )
      end

      private

      def boat_ins
        @boat_ins ||= booking_guests_scope
          .where(boat_in_at: window)
          .order("booking_guests.boat_in_at ASC")
          .map { |bg| row_for(bg, bg.boat_in_at) }
      end

      def boat_outs
        @boat_outs ||= booking_guests_scope
          .where(boat_out_at: window)
          .order("booking_guests.boat_out_at ASC")
          .map { |bg| row_for(bg, bg.boat_out_at) }
      end

      def window
        ::Boats::Schedule.day_range(hotel: @hotel, from: @start_date, to: @end_date)
      end

      def booking_guests_scope
        BookingGuest.joins(:booking)
                    .where(bookings: { hotel_id: @hotel.id })
                    .includes(booking: { booking_rooms: :room_type }, guest: {})
      end

      # The two directions differ only in which timestamp they carry.
      def row_for(bg, boat_at)
        booking = bg.booking
        {
          booking_guest_id: bg.id,
          guest_name: bg.name_snapshot || bg.guest.name,
          room_type: booking.booking_rooms.map { |br| br.room_type&.name }.compact.uniq.join(", ").presence || "—",
          room_number: booking.booking_rooms.map(&:room_number).compact.join(", ").presence || "—",
          check_in: booking.check_in,
          check_out: booking.check_out,
          arrival_date: booking.check_in.strftime("%d %b %Y"),
          departure_date: booking.check_out.strftime("%d %b %Y"),
          stay_dates: "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}",
          confirmation_token: booking.confirmation_token,
          boat_time: format_boat_time(boat_at),
          boat_at: boat_at
        }
      end

      def format_boat_time(value)
        return "—" if value.blank?

        value.in_time_zone(@hotel.hotel_time_zone).strftime("%I:%M %p")
      end
    end
  end
end
