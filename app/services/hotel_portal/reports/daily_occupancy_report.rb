# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyOccupancyReport
      Result = Struct.new(:start_date, :end_date, :rows, :totals, keyword_init: true)

      SOLD_STATUSES = %w[confirmed checked_in completed].freeze

      def initialize(hotel:, start_date:, end_date:, date_preset: nil)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @date_preset = date_preset.to_s
      end

      def call
        rows = date_range.map { |date| build_row(date) }
        rows = monthly? ? aggregate_monthly(rows) : rows
        sold_sum = rows.sum { |row| row[:rooms_sold] }
        available_sum = rows.sum { |row| row[:rooms_available] }
        revenue_sum = rows.sum { |row| row[:room_revenue] }
        day_use_sold_sum = rows.sum { |row| row[:day_use_sold] }
        day_use_revenue_sum = rows.sum { |row| row[:day_use_revenue] }
        tax_sum = rows.sum { |row| row[:tax_amount] }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          rows: rows,
          totals: {
            rooms_sold: sold_sum,
            rooms_available: available_sum,
            room_revenue: revenue_sum,
            day_use_sold: day_use_sold_sum,
            day_use_revenue: day_use_revenue_sum,
            tax_amount: tax_sum,
            total_revenue: revenue_sum + day_use_revenue_sum + tax_sum,
            occupancy_rate: ratio(sold_sum, available_sum),
            adr: ratio(revenue_sum, sold_sum),
            revpar: ratio(revenue_sum, available_sum)
          }
        )
      end

      private

      def monthly?
        @date_preset == "this_year"
      end

      def aggregate_monthly(rows)
        rows.group_by { |row| row[:date].beginning_of_month }
            .map do |month, month_rows|
          sold = month_rows.sum { |row| row[:rooms_sold].to_i }
          available = month_rows.sum { |row| row[:rooms_available].to_i }
          revenue = month_rows.sum { |row| row[:room_revenue].to_d }
          day_use_sold = month_rows.sum { |row| row[:day_use_sold].to_i }
          day_use_revenue = month_rows.sum { |row| row[:day_use_revenue].to_d }
          tax = month_rows.sum { |row| row[:tax_amount].to_d }

          {
            date: month,
            rooms_sold: sold,
            rooms_available: available,
            room_revenue: revenue.round(2),
            day_use_sold: day_use_sold,
            day_use_revenue: day_use_revenue.round(2),
            tax_amount: tax.round(2),
            total_revenue: (revenue + day_use_revenue + tax).round(2),
            occupancy_rate: ratio(sold, available),
            adr: ratio(revenue, sold),
            revpar: ratio(revenue, available)
          }
        end
      end

      def build_row(date)
        sold = 0
        revenue = 0.to_d

        sold_bookings.each do |booking|
          next unless (booking.check_in.to_date...booking.check_out.to_date).cover?(date)

          sold += booked_room_quantity(booking)
          revenue += nightly_room_revenue(booking)
        end

        available = available_rooms_for(date)
        tax = tax_by_posting_date[date] || 0.to_d
        day_use = day_use_by_date[date] || { sold: 0, revenue: 0.to_d }

        {
          date: date,
          rooms_sold: sold,
          rooms_available: available,
          room_revenue: revenue,
          day_use_sold: day_use[:sold],
          day_use_revenue: day_use[:revenue],
          tax_amount: tax,
          total_revenue: revenue + day_use[:revenue] + tax,
          occupancy_rate: ratio(sold, available),
          adr: ratio(revenue, sold),
          revpar: ratio(revenue, available)
        }
      end

      # Day use sits beside the overnight figures, never inside them: a room
      # sold for a few hours would inflate occupancy and drag ADR down. The
      # revenue still joins Total revenue so this report ties to Daily Revenue.
      def day_use_by_date
        @day_use_by_date ||= day_use_bookings.each_with_object({}) do |booking, by_date|
          date = booking.check_in.in_time_zone(@hotel.hotel_time_zone).to_date
          next unless (@start_date..@end_date).cover?(date)

          entry = by_date[date] ||= { sold: 0, revenue: 0.to_d }
          entry[:sold] += booked_room_quantity(booking)
          entry[:revenue] += booking_room_revenue(booking)
        end
      end

      def day_use_bookings
        zone = @hotel.hotel_time_zone
        window = @start_date.in_time_zone(zone).beginning_of_day..@end_date.in_time_zone(zone).end_of_day
        @hotel.bookings
              .where(status: SOLD_STATUSES, check_in: window)
              .where(id: BookingRoom.joins(:rate_plan).where.not(rate_plans: { day_use_hours: nil }).select(:booking_id))
              .includes(:booking_rooms)
      end

      def booking_room_revenue(booking)
        subtotal_sum = booking.booking_rooms.sum { |room| room.subtotal.to_d }
        subtotal_sum.positive? ? subtotal_sum : booking.total_amount.to_d
      end

      def tax_by_posting_date
        @tax_by_posting_date ||= FolioTransaction.joins(booking_folio: :booking)
          .where(bookings: { hotel_id: @hotel.id })
          .where(posting_date: @start_date..@end_date)
          .where(category: "tax")
          .group(:posting_date)
          .sum(:amount)
          .transform_keys(&:to_date)
      end

      def sold_bookings
        @sold_bookings ||= @hotel.bookings
                               .where(status: SOLD_STATUSES)
                               .where("check_in::date <= ? AND check_out::date > ?", @end_date, @start_date)
                               .includes(:booking_rooms)
      end

      def room_types
        @room_types ||= @hotel.room_types.to_a
      end

      def inventories_by_type_and_date
        @inventories_by_type_and_date ||= begin
          rows = RoomInventory.where(room_type_id: room_types.map(&:id), date: @start_date..@end_date)
          rows.index_by { |row| [ row.room_type_id, row.date ] }
        end
      end

      def available_rooms_for(date)
        room_types.sum do |room_type|
          inventory = inventories_by_type_and_date[[ room_type.id, date ]]
          next inventory.quantity.to_i if inventory&.status == "open"
          next 0 if inventory&.status == "closed"

          room_type.quantity.to_i
        end
      end

      def booked_room_quantity(booking)
        quantity = booking.booking_rooms.size
        quantity.positive? ? quantity : 1
      end

      def nightly_room_revenue(booking)
        nights = [ (booking.check_out.to_date - booking.check_in.to_date).to_i, 1 ].max
        subtotal_sum = booking.booking_rooms.sum { |room| room.subtotal.to_d }
        total_revenue = subtotal_sum.positive? ? subtotal_sum : booking.total_amount.to_d
        total_revenue / nights
      end

      def date_range
        (@start_date..@end_date).to_a
      end

      def ratio(numerator, denominator)
        return 0.to_d if denominator.to_d.zero?

        numerator.to_d / denominator.to_d
      end
    end
  end
end
