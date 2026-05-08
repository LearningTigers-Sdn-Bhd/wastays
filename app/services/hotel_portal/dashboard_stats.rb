# frozen_string_literal: true

module HotelPortal
  class DashboardStats
    def initialize(hotel)
      @hotel = hotel
    end

    def today_arrivals
      @hotel.bookings.active.where(check_in: Date.current)
    end

    def tomorrow_arrivals
      @hotel.bookings.active.where(check_in: Date.tomorrow)
    end

    def today_checkouts
      @hotel.bookings.active.where(check_out: Date.current)
    end

    def bookings_this_month_count
      @hotel.bookings.active.where(created_at: Time.current.all_month).count
    end

    def revenue_this_month
      @hotel.bookings.active.where(created_at: Time.current.all_month).sum(:total_amount)
    end

    def pending_actions_count
      arrival_window = Date.current..(Date.current + 1.day)
      @hotel.bookings.active
        .joins(:pre_checkin)
        .where(pre_checkins: { status: "pending" })
        .where(check_in: arrival_window)
        .count
    end

    def occupancy_snapshot(days: 7)
      (Date.current..(Date.current + (days - 1).days)).map do |date|
        # Correctly sum the quantity column from room_inventories
        total_inventory = @hotel.room_types.joins(:room_inventories)
                                .where(room_inventories: { date: date })
                                .sum("room_inventories.quantity")

        rooms_sold = @hotel.bookings.revenue_generating.where(":date >= check_in AND :date < check_out", date: date).count
        {
          date: date,
          total: total_inventory,
          sold: rooms_sold,
          percent: total_inventory > 0 ? (rooms_sold.to_f / total_inventory * 100).round : 0
        }
      end
    end
  end
end
