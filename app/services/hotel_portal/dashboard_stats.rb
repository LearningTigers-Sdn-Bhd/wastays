# frozen_string_literal: true

module HotelPortal
  class DashboardStats
    def initialize(hotel)
      @hotel = hotel
    end

    def today_arrivals
      @hotel.bookings.active.checking_in_on(Date.current, @hotel.hotel_time_zone)
    end

    def tomorrow_arrivals
      @hotel.bookings.active.checking_in_on(Date.tomorrow, @hotel.hotel_time_zone)
    end

    def today_checkouts
      @hotel.bookings.active.checking_out_on(Date.current, @hotel.hotel_time_zone)
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
        .checking_in_between(arrival_window.begin, arrival_window.end, @hotel.hotel_time_zone)
        .count
    end

    def live_inventory
      date = Date.current
      @hotel.room_types.order(:id).map do |room_type|
        inventory = room_type.room_inventories.find_by(date: date)

        total_capacity = room_type.quantity
        remaining = inventory&.status == "closed" ? 0 : (inventory&.quantity || total_capacity)

        # Count actual sold rooms from bookings
        sold = @hotel.bookings.revenue_generating
                     .joins(:booking_rooms)
                     .where(booking_rooms: { room_type_id: room_type.id })
                     .where(":date >= check_in::date AND :date < check_out::date", date: date)
                     .count

        percentage = total_capacity > 0 ? (sold.to_f / total_capacity * 100).round : 0

        {
          room_type: room_type,
          name: room_type.name,
          total: total_capacity,
          sold: sold,
          remaining: remaining,
          percentage: percentage,
          status: inventory&.status || "open"
        }
        end
        end
    def occupancy_snapshot(days: 7)
      (Date.current..(Date.current + (days - 1).days)).map do |date|
        # Correctly sum the quantity column from room_inventories
        total_inventory = @hotel.room_types.joins(:room_inventories)
                                .where(room_inventories: { date: date })
                                .sum("room_inventories.quantity")

        rooms_sold = @hotel.bookings.revenue_generating.where(":date >= check_in::date AND :date < check_out::date", date: date).count
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
