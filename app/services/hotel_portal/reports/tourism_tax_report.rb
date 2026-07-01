# frozen_string_literal: true

module HotelPortal
  module Reports
    class TourismTaxReport
      IN_HOUSE_STATUSES = %w[checked_in checkout_required].freeze

      Result = Struct.new(:start_date, :end_date, :rows, :totals, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def call
        rows = bookings.map { |booking| row_for(booking) }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          rows: rows,
          totals: {
            guest_count: rows.size,
            total_due: rows.sum { |row| row[:tax_due] },
            total_collected: rows.sum { |row| row[:tax_collected] }
          }
        )
      end

      private

      def bookings
        @hotel.bookings
              .where(status: IN_HOUSE_STATUSES)
              .where("check_in <= ? AND check_out >= ?", @end_date, @start_date)
              .where.not(guest_country: [ nil, "" ])
              .where.not("LOWER(guest_country) = ?", "malaysia")
              .where("COALESCE(tourism_tax_amount, 0) > 0")
              .includes(booking_rooms: :room_type)
              .order(:check_in, :created_at, :id)
      end

      def row_for(booking)
        due = booking.tourism_tax_amount.to_d

        {
          booking_id: booking.id,
          guest_name: booking.guest_name,
          guest_country: booking.guest_country,
          booking_reference: booking.invoice_number.presence || booking.confirmation_token,
          check_in: booking.check_in,
          check_out: booking.check_out,
          nights: (booking.check_out.to_date - booking.check_in.to_date).to_i,
          room_numbers: room_numbers(booking),
          tax_due: due,
          tax_collected: booking.tourism_tax_collected? ? due : 0.to_d,
          collection_status: booking.tourism_tax_collected? ? "Collected" : "Pending"
        }
      end

      def room_numbers(booking)
        numbers = booking.booking_rooms.sort_by(&:id).map { |room| room.room_number.presence || "TBA" }
        numbers.presence&.join(", ") || "TBA"
      end
    end
  end
end
