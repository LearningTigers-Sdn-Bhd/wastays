# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueSourceBookings
      Entry = Struct.new(:id, :confirmation_token, :guest_name, :check_in, :check_out, :status, keyword_init: true)
      Result = Struct.new(:source_label, :start_date, :end_date, :entries, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:, source:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @source = source.to_s
      end

      def call
        Result.new(
          source_label: @source,
          start_date: @start_date,
          end_date: @end_date,
          entries: entries
        )
      end

      private

      def entries
        bookings.filter_map do |booking|
          next unless BookingSourceLabel.normalize(booking.source) == @source

          Entry.new(
            id: booking.id,
            confirmation_token: booking.confirmation_token,
            guest_name: booking.guest_name,
            check_in: booking.check_in,
            check_out: booking.check_out,
            status: booking.status
          )
        end.sort_by(&:check_in)
      end

      def bookings
        Booking
          .where(id: booking_ids)
          .order(:check_in)
      end

      def booking_ids
        FolioTransaction.joins(booking_folio: :booking)
          .where(bookings: { hotel_id: @hotel.id })
          .where(posting_date: @start_date..@end_date)
          .distinct
          .pluck("bookings.id")
      end
    end
  end
end
