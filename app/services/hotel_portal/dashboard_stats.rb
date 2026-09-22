# frozen_string_literal: true

module HotelPortal
  class DashboardStats
    def initialize(hotel)
      @hotel = hotel
    end

    def today_arrivals
      @hotel.bookings.active.includes(:pre_checkin).checking_in_on(Date.current, @hotel.hotel_time_zone)
    end

    def tomorrow_arrivals
      @hotel.bookings.active.checking_in_on(Date.tomorrow, @hotel.hotel_time_zone)
    end

    def today_checkouts
      @hotel.bookings.active.checking_out_on(Date.current, @hotel.hotel_time_zone)
    end

    # .active deliberately excludes "completed" (and "no_show") -- right for
    # the operational views below, where a stay already checked out is not an
    # upcoming arrival or action, but wrong here: a guest who checked out
    # earlier this month still generated real revenue, and .active silently
    # dropped it from the month's own total the moment they left.
    # .revenue_generating is the scope built for exactly this -- everything
    # that produced revenue, cancelled and voided excepted.
    def bookings_this_month_count
      @hotel.bookings.revenue_generating.where(created_at: Time.current.all_month).count
    end

    def revenue_this_month
      @hotel.bookings.revenue_generating.where(created_at: Time.current.all_month).sum(:total_amount)
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
        # Already net of every sale: Bookings::InventoryManager decrements this
        # by one for each booking taken and puts it back on release, so it is
        # "what's left to sell", not "total capacity" -- subtracting `sold`
        # from it again double-counted every sale, which is why remaining +
        # sold stopped adding up to total the moment a room type sold anything
        # today (a quiet day, sold == 0, hid it completely).
        available_capacity = inventory&.quantity || total_capacity

        # Its own count, not derived from available_capacity: shown as its own
        # figure, and a real discrepancy between the two is worth being able to
        # see rather than papering over by deriving one from the other.
        sold = @hotel.bookings.revenue_generating
                     .joins(:booking_rooms)
                     .where(booking_rooms: { room_type_id: room_type.id })
                     .where(":date >= check_in::date AND :date < check_out::date", date: date)
                     .count

        remaining = inventory&.status == "closed" ? 0 : [ available_capacity, 0 ].max

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
