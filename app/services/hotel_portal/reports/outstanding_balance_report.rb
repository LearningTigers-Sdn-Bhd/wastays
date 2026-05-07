# frozen_string_literal: true

module HotelPortal
  module Reports
    class OutstandingBalanceReport
      Result = Struct.new(:start_date, :end_date, :rows, :totals, keyword_init: true)

      INCLUDED_STATUSES = %w[confirmed checked_in completed].freeze

      def initialize(hotel:, start_date:, end_date:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def call
        rows = filtered_bookings.map { |booking| row_for(booking) }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          rows: rows,
          totals: {
            booking_count: rows.size,
            outstanding_amount: rows.sum { |row| row[:outstanding_amount].to_d }
          }
        )
      end

      private

      def filtered_bookings
        @hotel.bookings
              .where(status: INCLUDED_STATUSES)
              .where.not(payment_status: "captured")
              .where(check_in: @start_date..@end_date)
              .includes(:booking_notes, booking_rooms: :room_type)
              .order(:check_in, :created_at, :id)
      end

      def row_for(booking)
        {
          booking_id: booking.id,
          guest_name: booking.guest_name,
          confirmation_token: booking.confirmation_token,
          payment_status: booking.payment_status.to_s.humanize,
          stay_dates: "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}",
          room_details: room_details(booking),
          room_numbers: room_numbers(booking),
          outstanding_amount: booking.total_amount.to_d,
          latest_note: latest_note(booking)
        }
      end

      def room_details(booking)
        details = booking.booking_rooms.map do |room|
          snapshot_name = room.room_type_snapshot.is_a?(Hash) ? room.room_type_snapshot["name"].presence : nil
          room_name = snapshot_name || room.room_type&.name || "Room"
          "#{room.quantity}x #{room_name}"
        end

        details.presence&.join(", ") || "No rooms assigned"
      end

      def room_numbers(booking)
        numbers = booking.booking_rooms.map { |room| room.room_number.presence || "TBA" }
        numbers.presence&.join(", ") || "TBA"
      end

      def latest_note(booking)
        booking.booking_notes.max_by(&:created_at)&.body.to_s
      end
    end
  end
end
