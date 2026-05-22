# frozen_string_literal: true

module HotelPortal
  module Reports
    class ManagersFlashReport
      Result = Struct.new(:start_date, :end_date, :rows, :totals, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def call
        # 1. Fetch Daily Data
        daily_metrics = fetch_daily_metrics

        # 2. Calculate Totals
        totals = calculate_totals(daily_metrics)

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          rows: daily_metrics,
          totals: totals
        )
      end

      private

      def fetch_daily_metrics
        # Generate date series for the range to ensure we have rows for every day
        dates = (@start_date..@end_date).to_a

        # Fetch occupancy and revenue metrics from bookings and inventory
        occupancy_data = fetch_occupancy_data
        revenue_data = fetch_revenue_data

        dates.map do |date|
          occ = occupancy_data[date] || { rooms_sold: 0, rooms_available: 0, booking_revenue: 0.to_d }
          rev = revenue_data[date] || { room_revenue: 0.to_d, tax_amount: 0.to_d }

          rooms_sold = occ[:rooms_sold]
          rooms_available = occ[:rooms_available]

          # We use booking_revenue (prorated subtotal) for ADR/RevPAR to match DailyOccupancyReport
          # but we also show actual posted folio revenue (room_revenue) to match DailyRevenueReport
          booking_revenue = occ[:booking_revenue]
          room_revenue = rev[:room_revenue]
          tax_amount = rev[:tax_amount]

          {
            date: date,
            rooms_sold: rooms_sold,
            rooms_available: rooms_available,
            occupancy_rate: ratio(rooms_sold, rooms_available),
            adr: ratio(booking_revenue, rooms_sold),
            revpar: ratio(booking_revenue, rooms_available),
            booking_revenue: booking_revenue,
            room_revenue: room_revenue,
            tax_amount: tax_amount,
            total_revenue: room_revenue + tax_amount
          }
        end
      end

      def fetch_occupancy_data
        # This query calculates available rooms and sold rooms per day
        # Sold rooms are based on bookings that cover the date

        # Part A: Available Rooms from Inventory
        # We need to sum up inventory for each date
        inventory_sql = <<-SQL
          SELECT#{' '}
            gs.date,
            SUM(
              CASE#{' '}
                WHEN ri.status = 'open' THEN ri.quantity
                WHEN ri.status = 'closed' THEN 0
                ELSE rt.quantity
              END
            ) as available
          FROM generate_series(?::date, ?::date, '1 day'::interval) gs(date)
          CROSS JOIN room_types rt
          LEFT JOIN room_inventories ri ON ri.room_type_id = rt.id AND ri.date = gs.date
          WHERE rt.hotel_id = ?
          GROUP BY gs.date
        SQL

        availability = ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([ inventory_sql, @start_date, @end_date, @hotel.id ])
        ).each_with_object({}) do |row, h|
          date = row["date"]
          date = Date.parse(date) if date.is_a?(String)
          h[date.to_date] = row["available"].to_i
        end

        # Part B: Sold Rooms and Prorated Revenue from Bookings
        # Logic matches DailyOccupancyReport: (check_in...check_out) cover date
        bookings_sql = <<-SQL
          SELECT#{' '}
            gs.date,
            SUM(GREATEST(br.quantity, 1)) as sold,
            SUM(br.subtotal / GREATEST(DATEDIFF(b.check_out, b.check_in), 1)) as revenue
          FROM generate_series(?::date, ?::date, '1 day'::interval) gs(date)
          INNER JOIN bookings b ON b.hotel_id = ?#{' '}
            AND b.status IN ('confirmed', 'checked_in', 'completed')
            AND b.check_in <= gs.date#{' '}
            AND b.check_out > gs.date
          INNER JOIN booking_rooms br ON br.booking_id = b.id
          GROUP BY gs.date
        SQL

        # DATEDIFF is not standard Postgres, use subtraction
        bookings_sql.gsub!("DATEDIFF(b.check_out, b.check_in)", "(b.check_out - b.check_in)")

        occupancy = ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([ bookings_sql, @start_date, @end_date, @hotel.id ])
        ).each_with_object({}) do |row, h|
          date = row["date"]
          date = Date.parse(date) if date.is_a?(String)
          date = date.to_date
          h[date] = {
            rooms_sold: row["sold"].to_i,
            rooms_available: availability[date] || 0,
            booking_revenue: row["revenue"].to_d
          }
        end

        # Fill in available rooms for dates without bookings
        availability.each do |date, avail|
          occupancy[date] ||= { rooms_sold: 0, rooms_available: avail, booking_revenue: 0.to_d }
        end

        occupancy
      end

      def fetch_revenue_data
        # This query calculates posted revenue from FolioTransactions
        # Logic matches DailyRevenueReport: posting_date in range
        sql = <<-SQL
          SELECT#{' '}
            ft.posting_date,
            SUM(CASE WHEN (ft.category = 'accommodation' OR (ft.transaction_type = 'adjustment' AND rft.category = 'accommodation')) THEN ft.amount ELSE 0 END) as room_revenue,
            SUM(CASE WHEN (ft.category = 'tax' OR (ft.transaction_type = 'adjustment' AND rft.category = 'tax')) THEN ft.amount ELSE 0 END) as tax_amount
          FROM folio_transactions ft
          INNER JOIN booking_folios bf ON bf.id = ft.booking_folio_id
          INNER JOIN bookings b ON b.id = bf.booking_id
          LEFT JOIN folio_transactions rft ON rft.id = ft.reversal_of_transaction_id
          WHERE b.hotel_id = ?
            AND ft.posting_date BETWEEN ? AND ?
            AND (
              ft.category IN ('accommodation', 'tax') OR#{' '}
              (ft.transaction_type = 'adjustment' AND rft.category IN ('accommodation', 'tax'))
            )
          GROUP BY ft.posting_date
        SQL

        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([ sql, @hotel.id, @start_date, @end_date ])
        ).each_with_object({}) do |row, h|
          date = row["posting_date"]
          date = Date.parse(date) if date.is_a?(String)
          h[date.to_date] = {
            room_revenue: row["room_revenue"].to_d,
            tax_amount: row["tax_amount"].to_d
          }
        end
      end

      def calculate_totals(rows)
        rooms_sold = rows.sum { |r| r[:rooms_sold] }
        rooms_available = rows.sum { |r| r[:rooms_available] }
        room_revenue = rows.sum { |r| r[:room_revenue] }
        tax_amount = rows.sum { |r| r[:tax_amount] }

        # For ADR/RevPAR we use the sum of daily booking_revenue (prorated subtotals)
        # but for Total Revenue we use the sum of posted folio room_revenue + tax.
        # This aligns with how the individual reports work.
        total_booking_revenue = rows.sum { |r| r[:booking_revenue] || 0.to_d }

        {
          rooms_sold: rooms_sold,
          rooms_available: rooms_available,
          occupancy_rate: ratio(rooms_sold, rooms_available),
          adr: ratio(total_booking_revenue, rooms_sold),
          revpar: ratio(total_booking_revenue, rooms_available),
          room_revenue: room_revenue,
          tax_amount: tax_amount,
          total_revenue: room_revenue + tax_amount
        }
      end

      def ratio(numerator, denominator)
        return 0.to_d if denominator.to_d.zero?

        numerator.to_d / denominator.to_d
      end
    end
  end
end
