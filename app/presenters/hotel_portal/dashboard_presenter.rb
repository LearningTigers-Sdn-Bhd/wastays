# frozen_string_literal: true

module HotelPortal
  class DashboardPresenter
    attr_reader :hotel, :stats, :recent_bookings

    def initialize(hotel, stats, recent_bookings)
      @hotel = hotel
      @stats = stats
      @recent_bookings = recent_bookings
    end

    def revenue_this_month_formatted
      revenue = stats.revenue_this_month || 0
      "RM #{ActionController::Base.helpers.number_with_delimiter(ActionController::Base.helpers.number_with_precision(revenue, precision: 2))}"
    end

    def bookings_this_month_count
      stats.bookings_this_month_count || 0
    end

    def today_arrivals_count
      stats.today_arrivals.count
    end

    def today_checkouts_count
      stats.today_checkouts.count
    end

    def live_inventory_items
      stats.live_inventory.map do |item|
        remaining = item[:remaining]
        {
          name: item[:name],
          total: item[:total],
          sold: item[:sold],
          remaining: remaining,
          percentage: item[:percentage],
          remaining_label: "#{remaining} #{'Room'.pluralize(remaining)} Left",
          remaining_color_class: remaining > 0 ? "text-emerald-600" : "text-rose-600"
        }
      end
    end

    def occupancy_snapshot_days
      stats.occupancy_snapshot.map do |day|
        {
          date_label: day[:date].strftime("%a, %b %d"),
          percent: day[:percent],
          sold: day[:sold],
          total: day[:total] || 0,
          percent_text_class: occupancy_percent_text_class(day[:percent]),
          percent_bar_class: occupancy_percent_bar_class(day[:percent])
        }
      end
    end

    def pending_actions_count
      stats.pending_actions_count
    end

    def pending_actions_label
      count = pending_actions_count
      "#{ActionController::Base.helpers.pluralize(count, 'guest')} pending review."
    end

    private

    def occupancy_percent_text_class(percent)
      case percent
      when 80..Float::INFINITY then "text-emerald-600"
      when 40...80 then "text-amber-600"
      else "text-rose-600"
      end
    end

    def occupancy_percent_bar_class(percent)
      case percent
      when 80..Float::INFINITY then "bg-emerald-500"
      when 40...80 then "bg-amber-500"
      else "bg-rose-500"
      end
    end
  end
end
