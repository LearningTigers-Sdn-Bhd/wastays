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

      Result = Struct.new(
        :start_date, :end_date, :totals, :rows, :source_rows, :tax_names,
        :extra_rows, :extra_totals, :extra_tax_names, keyword_init: true
      ) do
        # One column per tax, so every table and export reads its columns from here.
        def headers(label)
          [ label, "Bookings", "Accommodation", "Room Fees", "Extra Charges", *tax_names, "Total Charges", "Adjustments", "Net Revenue" ]
        end

        def values(row)
          [
            row[:booking_count], row[:accommodation], row[:room_fees], row[:other_charges],
            *tax_names.map { |name| row[:taxes].fetch(name, 0.to_d) },
            row[:total_charges], row[:adjustments], row[:net_revenue]
          ]
        end

        def extra_headers
          [ "Item", "Count", "Amount", *extra_tax_names, "Total Incl. Tax" ]
        end

        def extra_values(row)
          [ row[:count], row[:amount], *extra_tax_names.map { |name| row[:taxes].fetch(name, 0.to_d) }, row[:total] ]
        end
      end

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

        daily_stats = Hash.new { |h, k| h[k] = new_stats }
        source_stats = Hash.new { |h, k| h[k] = new_stats }

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

          next unless accounting.tax_charge?(tx)

          tax_name = accounting.tax_name_for(tx)
          daily_stats[date][:taxes][tax_name] += tx.amount
          source_stats[source][:taxes][tax_name] += tx.amount
        end

        tax_names = daily_stats.values.flat_map { |stats| stats[:taxes].keys }.uniq.sort

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
          room_fees: rows.sum { |r| r[:room_fees] },
          other_charges: rows.sum { |r| r[:other_charges] },
          tax: rows.sum { |r| r[:tax] },
          taxes: tax_names.index_with { |name| rows.sum { |r| r[:taxes].fetch(name, 0.to_d) } },
          total_charges: rows.sum { |r| r[:total_charges] },
          adjustments: rows.sum { |r| r[:adjustments] },
          net_revenue: rows.sum { |r| r[:net_revenue] }
        }

        extra_rows = extra_charge_rows(accounting, transactions)

        Result.new(
          start_date: @start_date, end_date: @end_date, totals: totals, rows: rows, source_rows: source_rows,
          tax_names: tax_names, extra_rows: extra_rows, extra_totals: extra_totals_for(extra_rows),
          extra_tax_names: extra_rows.flat_map { |row| row[:taxes].keys }.uniq.sort
        )
      end

      private

      def new_stats
        { booking_ids: Set.new, taxes: Hash.new(0.to_d) }.merge(DailyRevenueAccounting::ZERO_BUCKET)
      end

      # One row per extra charge item. A tax line joins the item that its parent charge belongs to.
      def extra_charge_rows(accounting, transactions)
        items = Hash.new { |h, k| h[k] = { count: 0, amount: 0.to_d, taxes: Hash.new(0.to_d) } }
        item_by_charge_id = {}

        transactions.select { |tx| accounting.extra_charge?(tx) }.each do |tx|
          name = item_by_charge_id[tx.id] = accounting.item_name_for(tx)
          items[name][:count] += 1
          items[name][:amount] += tx.amount
        end

        transactions.select { |tx| accounting.tax_charge?(tx) }.each do |tx|
          name = item_by_charge_id[accounting.parent_id_for(tx)]
          items[name][:taxes][accounting.tax_name_for(tx)] += tx.amount if name
        end

        items.map { |name, stats| extra_row_for(name, stats) }.sort_by { |row| [ -row[:amount], row[:item] ] }
      end

      def extra_row_for(name, stats)
        taxes = stats[:taxes].transform_values { |amount| amount.round(2) }
        { item: name, count: stats[:count], amount: stats[:amount].round(2), taxes: taxes,
          total: (stats[:amount] + taxes.values.sum).round(2) }
      end

      def extra_totals_for(extra_rows)
        taxes = extra_rows.flat_map { |row| row[:taxes].keys }.uniq.sort
        {
          count: extra_rows.sum { |row| row[:count] },
          amount: extra_rows.sum { |row| row[:amount] },
          taxes: taxes.index_with { |name| extra_rows.sum { |row| row[:taxes].fetch(name, 0.to_d) } },
          total: extra_rows.sum { |row| row[:total] }
        }
      end

      def row_for(accounting, date, raw_stats)
        stats = accounting.with_derived_fields(raw_stats)
        {
          date: date,
          booking_count: stats[:booking_ids].size,
          accommodation: stats[:accommodation].round(2),
          room_fees: stats[:room_fees].round(2),
          other_charges: stats[:other_charges].round(2),
          tax: stats[:tax].round(2),
          taxes: stats[:taxes].transform_values { |amount| amount.round(2) },
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
          month_stats = new_stats
          daily_stats.each do |date, stats|
            next unless date.beginning_of_month == month

            month_stats[:booking_ids].merge(stats[:booking_ids])
            stats[:taxes].each { |name, amount| month_stats[:taxes][name] += amount }
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
