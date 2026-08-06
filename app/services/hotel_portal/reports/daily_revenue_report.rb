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

      def initialize(hotel:, start_date:, end_date:, date_preset: nil)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @date_preset = date_preset.to_s
      end

      def call
        transactions = FolioTransaction.joins(booking_folio: :booking)
                         .where(bookings: { hotel_id: @hotel.id })
                         .where(posting_date: @start_date..@end_date)
                         .where(transaction_type: %w[charge adjustment])
                         .select(
                           "folio_transactions.*",
                           "bookings.source as booking_source",
                           "bookings.id as booking_id"
                         )

        accounting = DailyRevenueAccounting.new(transactions)

        daily_stats = Hash.new { |h, k| h[k] = { booking_ids: Set.new }.merge(DailyRevenueAccounting::ZERO_BUCKET) }
        source_stats = Hash.new { |h, k| h[k] = { booking_ids: Set.new }.merge(DailyRevenueAccounting::ZERO_BUCKET) }

        transactions.each do |tx|
          date = tx.posting_date
          source = normalize_source(tx.booking_source)
          booking_id = tx.booking_id

          daily_stats[date][:booking_ids] << booking_id
          source_stats[source][:booking_ids] << booking_id

          accounting.bucket_for(tx).each do |key, amount|
            daily_stats[date][key] += amount
            source_stats[source][key] += amount
          end
        end

        rows = if monthly?
          aggregate_monthly(accounting, daily_stats)
        else
          daily_stats.keys.sort.map { |date| row_for(accounting, date, daily_stats[date]) }
        end

        source_rows = source_stats.map { |source, stats| source_row_for(accounting, source, stats) }
                                  .sort_by { |row| -row[:total_charges] }

        totals = {
          booking_count: transactions.map(&:booking_id).uniq.size,
          accommodation: rows.sum { |r| r[:accommodation] },
          other_charges: rows.sum { |r| r[:other_charges] },
          tax: rows.sum { |r| r[:tax] },
          total_charges: rows.sum { |r| r[:total_charges] },
          adjustments: rows.sum { |r| r[:adjustments] },
          net_revenue: rows.sum { |r| r[:net_revenue] }
        }

        Result.new(start_date: @start_date, end_date: @end_date, totals: totals, rows: rows, source_rows: source_rows)
      end

      private

      def row_for(accounting, date, raw_stats)
        stats = accounting.with_derived_fields(raw_stats)
        {
          date: date,
          booking_count: stats[:booking_ids].size,
          accommodation: stats[:accommodation].round(2),
          other_charges: stats[:other_charges].round(2),
          tax: stats[:tax].round(2),
          total_charges: stats[:total_charges].round(2),
          adjustments: stats[:adjustments].round(2),
          net_revenue: stats[:net_revenue].round(2)
        }
      end

      def source_row_for(accounting, source, raw_stats)
        row_for(accounting, nil, raw_stats).merge(source: source).except(:date)
      end

      def monthly?
        @date_preset == "this_year"
      end

      def each_month_in_range
        month = @start_date.beginning_of_month
        last_month = @end_date.beginning_of_month
        while month <= last_month
          yield month
          month = month.next_month
        end
      end

      def aggregate_monthly(accounting, daily_stats)
        months = []
        each_month_in_range { |month| months << month }

        months.map do |month|
          month_stats = { booking_ids: Set.new }.merge(DailyRevenueAccounting::ZERO_BUCKET)
          daily_stats.each do |date, stats|
            next unless date.beginning_of_month == month

            month_stats[:booking_ids].merge(stats[:booking_ids])
            DailyRevenueAccounting::ZERO_BUCKET.each_key { |key| month_stats[key] += stats[key] }
          end
          row_for(accounting, month, month_stats)
        end
      end

      def normalize_source(source)
        source_key = source.to_s.strip
        source_key = "unknown" if source_key.empty?
        SOURCE_LABELS[source_key] || source_key.titleize.presence || "Others"
      end
    end
  end
end
