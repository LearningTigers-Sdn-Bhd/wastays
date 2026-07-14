# frozen_string_literal: true

module HotelPortal
  module Reports
    class BiboReport
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
          .where(bookings: { check_in: @start_date..@end_date })
          .or(booking_guests_scope.where(boat_in_at: @start_date.beginning_of_day..@end_date.end_of_day))
          .order("bookings.check_in ASC, booking_guests.boat_in_at ASC NULLS FIRST")
          .map { |bg| row_for_boat_in(bg) }
      end

      def boat_outs
        @boat_outs ||= booking_guests_scope
          .where(bookings: { check_out: @start_date..@end_date })
          .or(booking_guests_scope.where(boat_out_at: @start_date.beginning_of_day..@end_date.end_of_day))
          .order("bookings.check_out ASC, booking_guests.boat_out_at ASC NULLS FIRST")
          .map { |bg| row_for_boat_out(bg) }
      end

      def booking_guests_scope
        BookingGuest.joins(:booking)
                    .where(bookings: { hotel_id: @hotel.id })
                    .includes(booking: { booking_rooms: :room_type }, guest: {})
      end

      def row_for_boat_in(bg)
        booking = bg.booking
        {
          guest_name: bg.name_snapshot || bg.guest.name,
          room_type: booking.booking_rooms.map { |br| br.room_type&.name }.compact.uniq.join(", ").presence || "—",
          room_number: booking.booking_rooms.map(&:room_number).compact.join(", ").presence || "—",
          check_in: booking.check_in,
          check_out: booking.check_out,
          stay_dates: "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}",
          confirmation_token: booking.confirmation_token,
          boat_time: format_boat_time(bg.boat_in_at),
          boat_at: bg.boat_in_at
        }
      end

      def row_for_boat_out(bg)
        booking = bg.booking
        {
          guest_name: bg.name_snapshot || bg.guest.name,
          room_type: booking.booking_rooms.map { |br| br.room_type&.name }.compact.uniq.join(", ").presence || "—",
          room_number: booking.booking_rooms.map(&:room_number).compact.join(", ").presence || "—",
          check_in: booking.check_in,
          check_out: booking.check_out,
          stay_dates: "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}",
          confirmation_token: booking.confirmation_token,
          boat_time: format_boat_time(bg.boat_out_at),
          boat_at: bg.boat_out_at
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
