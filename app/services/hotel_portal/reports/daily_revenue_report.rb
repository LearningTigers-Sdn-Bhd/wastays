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
        # Query transactions within the date range for the hotel
        # Include accommodation and tax categories, plus adjustments that reverse them
        transactions = FolioTransaction.joins(booking_folio: :booking)
                         .left_outer_joins(:reversal_of_transaction)
                         .where(bookings: { hotel_id: @hotel.id })
                         .where(posting_date: @start_date..@end_date)
                         .where(
                           "folio_transactions.category IN ('accommodation', 'tax') OR " \
                           "(folio_transactions.transaction_type = 'adjustment' AND reversal_of_transactions_folio_transactions.category IN ('accommodation', 'tax'))"
                         )
                         .select(
                           "folio_transactions.*",
                           "bookings.source as booking_source",
                           "bookings.id as booking_id",
                           "reversal_of_transactions_folio_transactions.category as reversed_category"
                         )

        daily_stats = Hash.new { |h, k| h[k] = { booking_ids: Set.new, room_revenue: 0.to_d, tax_amount: 0.to_d } }
        source_stats = Hash.new { |h, k| h[k] = { booking_ids: Set.new, room_revenue: 0.to_d, tax_amount: 0.to_d } }

        transactions.each do |tx|
          date = tx.posting_date
          source = normalize_source(tx.booking_source)
          amount = tx.amount.to_d
          category = tx.transaction_type == "adjustment" ? tx.reversed_category : tx.category

          if category == "accommodation"
            daily_stats[date][:room_revenue] += amount
            source_stats[source][:room_revenue] += amount
            daily_stats[date][:booking_ids] << tx.booking_id
            source_stats[source][:booking_ids] << tx.booking_id
          elsif category == "tax"
            daily_stats[date][:tax_amount] += amount
            source_stats[source][:tax_amount] += amount
          end
        end

        rows = (@start_date..@end_date).map do |date|
          stats = daily_stats[date]
          {
            date: date,
            booking_count: stats[:booking_ids].size,
            room_revenue: stats[:room_revenue].round(2),
            tax_amount: stats[:tax_amount].round(2),
            total_revenue: (stats[:room_revenue] + stats[:tax_amount]).round(2)
          }
        end

        source_rows = source_stats.map do |source, stats|
          {
            source: source,
            booking_count: stats[:booking_ids].size,
            room_revenue: stats[:room_revenue].round(2),
            tax_amount: stats[:tax_amount].round(2),
            total_revenue: (stats[:room_revenue] + stats[:tax_amount]).round(2)
          }
        end.sort_by { |row| -row[:total_revenue] }

        room_revenue = rows.sum { |r| r[:room_revenue] }
        tax_amount = rows.sum { |r| r[:tax_amount] }
        total_booking_ids = transactions.map(&:booking_id).uniq.size

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          totals: {
            booking_count: total_booking_ids,
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
