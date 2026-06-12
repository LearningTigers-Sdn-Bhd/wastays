# frozen_string_literal: true

module HotelPortal
  module Reports
    class OutstandingBalanceReport
      Result = Struct.new(:start_date, :end_date, :rows, :totals, keyword_init: true)

      INCLUDED_STATUSES = %w[confirmed checked_in completed].freeze
      BALANCE_SQL = <<~SQL.squish.freeze
        COALESCE(SUM(CASE
          WHEN folio_transactions.transaction_type = 'charge' THEN folio_transactions.amount
          WHEN folio_transactions.transaction_type = 'payment' THEN -folio_transactions.amount
          WHEN folio_transactions.transaction_type = 'adjustment' THEN folio_transactions.amount
          ELSE 0
        END), 0)
      SQL

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
              .joins(:booking_folio)
              .left_joins(booking_folio: :folio_transactions)
              .where(status: INCLUDED_STATUSES)
              .checking_in_between(@start_date, @end_date, @hotel.hotel_time_zone)
              .group("bookings.id")
              .having("#{BALANCE_SQL} > 0")
              .includes(:booking_notes, booking_folio: :folio_transactions, booking_rooms: :room_type)
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
          outstanding_amount: outstanding_amount_for(booking),
          latest_note: latest_note(booking)
        }
      end

      def outstanding_amount_for(booking)
        booking.booking_folio&.outstanding_balance.to_d
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
