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
          .distinct
          .order("bookings.check_in ASC, booking_guests.boat_in_at ASC NULLS FIRST")
          .map { |bg| row_for_boat_in(bg) }
      end

      def boat_outs
        @boat_outs ||= booking_guests_scope
          .where(bookings: { check_out: @start_date..@end_date })
          .or(booking_guests_scope.where(boat_out_at: @start_date.beginning_of_day..@end_date.end_of_day))
          .distinct
          .order("bookings.check_out ASC, booking_guests.boat_out_at ASC NULLS FIRST")
          .map { |bg| row_for_boat_out(bg) }
      end

      def booking_guests_scope
        BookingGuest.joins(:booking)
                    .where(bookings: { hotel_id: @hotel.id })
                    .includes(:booking, :guest)
      end

      def row_for_boat_in(bg)
        booking = bg.booking
        {
          guest_name: bg.name_snapshot || bg.guest.name,
          role: bg.role.humanize,
          room_number: booking.booking_rooms.map(&:room_number).compact.join(", ").presence || "TBA",
          check_in: booking.check_in,
          check_out: booking.check_out,
          stay_dates: "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}",
          confirmation_token: booking.confirmation_token,
          boat_time: bg.boat_in_at&.strftime("%I:%M %p") || "Pending",
          boat_at: bg.boat_in_at,
          status: bg.boat_in_at.present? ? "Boarded" : "Expected"
        }
      end

      def row_for_boat_out(bg)
        booking = bg.booking
        {
          guest_name: bg.name_snapshot || bg.guest.name,
          role: bg.role.humanize,
          room_number: booking.booking_rooms.map(&:room_number).compact.join(", ").presence || "TBA",
          check_in: booking.check_in,
          check_out: booking.check_out,
          stay_dates: "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}",
          confirmation_token: booking.confirmation_token,
          boat_time: bg.boat_out_at&.strftime("%I:%M %p") || "Pending",
          boat_at: bg.boat_out_at,
          status: bg.boat_out_at.present? ? "Boarded" : "Expected"
        }
      end
    end
  end
end
