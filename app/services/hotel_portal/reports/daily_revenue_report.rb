# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueReport
      SOURCE_LABELS = {
        "walk_in" => "Walk-in",
        "agoda" => "Agoda",
        "whatsapp" => "WhatsApp",
        "corporate" => "Corporate",
        "internal" => "Direct"
      }.freeze

      Result = Struct.new(:start_date, :end_date, :totals, :rows, :source_rows, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def call
        # Load bookings whose stay overlaps the report date range
        bookings = @hotel.bookings.revenue_generating
                         .where("check_in <= ? AND check_out > ?", @end_date, @start_date)

        # Allocate each booking's revenue across its stay nights
        daily_allocations = Hash.new { |h, k| h[k] = { booking_count: 0, room_revenue: 0.to_d, tax_amount: 0.to_d } }
        source_allocations = Hash.new { |h, k| h[k] = { booking_count: 0, room_revenue: 0.to_d, tax_amount: 0.to_d } }

        bookings.each do |booking|
          nights = [ (booking.check_out - booking.check_in).to_i, 1 ].max
          nightly_revenue = booking.total_amount.to_d / nights
          nightly_tax = booking.tourism_tax_applied? ? (booking.tourism_tax_amount.to_d / nights) : 0.to_d
          source = normalize_source(booking.source)

          stay_nights_in_range(booking).each_with_index do |date, idx|
            daily_allocations[date][:room_revenue] += nightly_revenue
            daily_allocations[date][:tax_amount] += nightly_tax
            # Count booking once — on its first night within the range
            daily_allocations[date][:booking_count] += 1 if idx == 0

            source_allocations[source][:room_revenue] += nightly_revenue
            source_allocations[source][:tax_amount] += nightly_tax
            source_allocations[source][:booking_count] += 1 if idx == 0
          end
        end

        rows = (@start_date..@end_date).map do |date|
          alloc = daily_allocations[date]
          {
            date: date,
            booking_count: alloc[:booking_count],
            room_revenue: alloc[:room_revenue].round(2),
            tax_amount: alloc[:tax_amount].round(2),
            total_revenue: (alloc[:room_revenue] + alloc[:tax_amount]).round(2)
          }
        end

        source_rows = source_allocations.map do |source, alloc|
          {
            source: source,
            booking_count: alloc[:booking_count],
            room_revenue: alloc[:room_revenue].round(2),
            tax_amount: alloc[:tax_amount].round(2),
            total_revenue: (alloc[:room_revenue] + alloc[:tax_amount]).round(2)
          }
        end.sort_by { |row| -row[:total_revenue] }

        room_revenue = rows.sum { |r| r[:room_revenue] }
        tax_amount = rows.sum { |r| r[:tax_amount] }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          totals: {
            booking_count: bookings.count,
            room_revenue: room_revenue,
            tax_amount: tax_amount,
            total_revenue: room_revenue + tax_amount
          },
          rows: rows,
          source_rows: source_rows
        )
      end

      private

      # Returns stay nights that fall within the report date range
      def stay_nights_in_range(booking)
        first_night = [ booking.check_in.to_date, @start_date ].max
        last_night  = [ booking.check_out.to_date - 1, @end_date ].min
        (first_night..last_night).to_a
      end

      def normalize_source(source)
        source_key = source.to_s.strip
        source_key = "unknown" if source_key.empty?
        SOURCE_LABELS[source_key] || source_key.titleize.presence || "Others"
      end
    end
  end
end
