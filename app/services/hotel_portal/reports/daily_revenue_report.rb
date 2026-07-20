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
        # Query all transactions within the date range
        transactions = FolioTransaction.joins(booking_folio: :booking)
                         .left_outer_joins(:reversal_of_transaction)
                         .where(bookings: { hotel_id: @hotel.id })
                         .where(posting_date: @start_date..@end_date)
                         .select(
                           "folio_transactions.*",
                           "bookings.source as booking_source",
                           "bookings.id as booking_id",
                           "reversal_of_transactions_folio_transactions.category as reversed_category"
                         )

        accounting = DailyRevenueAccounting.new(transactions)

        # Build daily stats
        daily_stats = Hash.new do |h, k|
          h[k] = { booking_ids: Set.new, discount: 0.to_d }.merge(DailyRevenueAccounting::ZERO_BUCKET)
        end

        source_stats = Hash.new do |h, k|
          h[k] = { booking_ids: Set.new, discount: 0.to_d }.merge(DailyRevenueAccounting::ZERO_BUCKET)
        end

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

          if tx.category == "discount" || tx.reversed_category == "discount"
            daily_stats[date][:discount] += tx.amount.to_d
            source_stats[source][:discount] += tx.amount.to_d
          end
        end

        rows = daily_stats.keys.sort.map do |date|
          stats = accounting.with_derived_fields(daily_stats[date])

          {
            date: date,
            booking_count: stats[:booking_ids].size,
            accommodation: stats[:accommodation].round(2),
            other_charges: stats[:other_charges].round(2),
            tax: stats[:tax].round(2),
            total_charges: stats[:total_charges].round(2),
            adjustments: stats[:adjustments].round(2),
            net_revenue: stats[:net_revenue].round(2),
            discount: stats[:discount].round(2),
            gateway_payment: stats[:gateway_payment].round(2),
            cash_payment: stats[:cash_payment].round(2),
            booking_payment: stats[:booking_payment].round(2),
            total_payments: stats[:total_payments].round(2),
            refund: stats[:refund].round(2),
            net_payments: stats[:net_payments].round(2),
            net_amount: stats[:net_payments].round(2)
          }
        end

        rows = monthly? ? aggregate_monthly(rows) : rows

        source_rows = source_stats.map do |source, raw_stats|
          stats = accounting.with_derived_fields(raw_stats)

          {
            source: source,
            booking_count: stats[:booking_ids].size,
            accommodation: stats[:accommodation].round(2),
            other_charges: stats[:other_charges].round(2),
            tax: stats[:tax].round(2),
            total_charges: stats[:total_charges].round(2),
            adjustments: stats[:adjustments].round(2),
            net_revenue: stats[:net_revenue].round(2),
            discount: stats[:discount].round(2),
            gateway_payment: stats[:gateway_payment].round(2),
            cash_payment: stats[:cash_payment].round(2),
            booking_payment: stats[:booking_payment].round(2),
            total_payments: stats[:total_payments].round(2),
            refund: stats[:refund].round(2),
            net_payments: stats[:net_payments].round(2),
            net_amount: stats[:net_payments].round(2)
          }
        end.sort_by { |row| -row[:total_charges] }

        totals = {
          booking_count: transactions.map(&:booking_id).uniq.size,
          accommodation: rows.sum { |r| r[:accommodation] },
          other_charges: rows.sum { |r| r[:other_charges] },
          tax: rows.sum { |r| r[:tax] },
          total_charges: rows.sum { |r| r[:total_charges] },
          adjustments: rows.sum { |r| r[:adjustments] },
          net_revenue: rows.sum { |r| r[:net_revenue] },
          discount: rows.sum { |r| r[:discount] },
          gateway_payment: rows.sum { |r| r[:gateway_payment] },
          cash_payment: rows.sum { |r| r[:cash_payment] },
          booking_payment: rows.sum { |r| r[:booking_payment] },
          total_payments: rows.sum { |r| r[:total_payments] },
          refund: rows.sum { |r| r[:refund] },
          net_payments: rows.sum { |r| r[:net_payments] },
          net_amount: rows.sum { |r| r[:net_payments] }
        }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          totals: totals,
          rows: rows,
          source_rows: source_rows
        )
      end

      private

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

      def aggregate_monthly(rows)
        rows_by_month = rows.group_by { |row| row[:date].beginning_of_month }

        months = []
        each_month_in_range { |month| months << month }

        months.map do |month|
          month_rows = rows_by_month[month] || []
          total_charges = month_rows.sum { |row| row[:total_charges].to_d }
          total_payments = month_rows.sum { |row| row[:total_payments].to_d }
          net_payments = month_rows.sum { |row| row[:net_payments].to_d }

          {
            date: month,
            booking_count: month_rows.sum { |row| row[:booking_count].to_i },
            accommodation: month_rows.sum { |row| row[:accommodation].to_d }.round(2),
            other_charges: month_rows.sum { |row| row[:other_charges].to_d }.round(2),
            tax: month_rows.sum { |row| row[:tax].to_d }.round(2),
            total_charges: total_charges.round(2),
            adjustments: month_rows.sum { |row| row[:adjustments].to_d }.round(2),
            net_revenue: month_rows.sum { |row| row[:net_revenue].to_d }.round(2),
            discount: month_rows.sum { |row| row[:discount].to_d }.round(2),
            gateway_payment: month_rows.sum { |row| row[:gateway_payment].to_d }.round(2),
            cash_payment: month_rows.sum { |row| row[:cash_payment].to_d }.round(2),
            booking_payment: month_rows.sum { |row| row[:booking_payment].to_d }.round(2),
            total_payments: total_payments.round(2),
            refund: month_rows.sum { |row| row[:refund].to_d }.round(2),
            net_payments: net_payments.round(2),
            net_amount: net_payments.round(2)
          }
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
