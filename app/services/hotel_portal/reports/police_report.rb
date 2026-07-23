# frozen_string_literal: true

module HotelPortal
  module Reports
    class PoliceReport
      Result = Struct.new(:start_date, :end_date, :rows, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def call
        Result.new(start_date: @start_date, end_date: @end_date, rows: scope.map { |booking| row_for(booking) })
      end

      private

      def scope
        @hotel.bookings
              .where(status: Booking::OCCUPYING_STATUSES)
              .where("check_in <= ? AND check_out >= ?", @end_date.end_of_day, @start_date.beginning_of_day)
              .includes(booking_guests: :guest, booking_rooms: :room_type)
              .order(:check_in, :check_out, :id)
      end

      def row_for(booking)
        primary_guest = booking.booking_guests.find(&:primary?) || booking.booking_guests.first
        guest = primary_guest&.guest
        date_of_birth = primary_guest&.date_of_birth_snapshot || guest&.date_of_birth || booking.guest_date_of_birth
        phone = primary_guest&.phone_snapshot.presence || guest&.phone || booking.guest_phone

        {
          booking_id: booking.id,
          guest_name: primary_guest&.name_snapshot.presence || guest&.name || booking.guest_name,
          confirmation_token: booking.confirmation_token,
          room_number: booking.booking_rooms.filter_map(&:room_number).presence&.join(", ") || "-",
          nationality: primary_guest&.country_snapshot.presence || guest&.country || booking.guest_country || "-",
          gender: (primary_guest&.gender_snapshot.presence || guest&.gender || booking.guest_gender)&.humanize || "-",
          date_of_birth: date_of_birth&.strftime("%d %b %Y") || "-",
          address: booking.guest_home_address.presence || "-",
          contact: phone.presence || "-",
          check_in_date: booking.check_in.to_date,
          scheduled_check_in: booking.check_in.in_time_zone(@hotel.hotel_time_zone).strftime("%d %b %Y"),
          actual_check_in: timestamp(booking.checked_in_at),
          scheduled_check_out: booking.check_out.in_time_zone(@hotel.hotel_time_zone).strftime("%d %b %Y"),
          actual_check_out: timestamp(booking.checked_out_at),
          nights_stayed: (booking.check_out.to_date - booking.check_in.to_date).to_i,
          status: booking.status.humanize
        }
      end

      def timestamp(value)
        value&.in_time_zone(@hotel.hotel_time_zone)&.strftime("%d %b %Y\n%I:%M %p") || "-"
      end
    end
  end
end
