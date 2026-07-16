module HotelPortal::ReportsHelper
  def guest_reports_date_range_label(report)
    if report.start_date == report.end_date
      report.start_date.strftime("%A, %d %b %Y")
    else
      "#{report.start_date.strftime('%d %b %Y')} - #{report.end_date.strftime('%d %b %Y')}"
    end
  end

  def guest_report_tabs_data(report, bibo_report, active_tab, grc_total_count, current_hotel, date_preset)
    tabs = [
      { label: "Arrivals", value: "arrivals", count: report.arrival_count },
      { label: "In-House", value: "in_house", count: report.in_house_count },
      { label: "Departures", value: "departures", count: report.departure_count },
      { label: "Checkout", value: "checkout", count: report.checkout_count },
      { label: "Registration Cards", value: "registration_cards", count: grc_total_count }
    ]

    if current_hotel.allow_boat_information?
      tabs << { label: "Boat Transfers", value: "bibo", count: bibo_report ? (bibo_report.boat_in_count + bibo_report.boat_out_count) : 0 }

      meal_prep_count = HotelPortal::Reports::MealPrepReport.new(
        hotel: current_hotel,
        start_date: report.start_date,
        end_date: report.end_date
      ).call.records.size
      tabs << { label: "Meal Prep", value: "meal_prep", count: meal_prep_count }
    end

    tabs.map do |tab|
      active = (tab[:value] == active_tab)
      path = guest_reports_hotel_reports_path(
        current_hotel,
        start_date: report.start_date,
        end_date: report.end_date,
        date_preset: date_preset,
        tab: tab[:value]
      )
      tab.merge(active: active, path: path)
    end
  end

  def show_metrics_cards?(active_tab)
    !%w[registration_cards bibo meal_prep].include?(active_tab)
  end

  def format_report_boat_time(boat_departure, hotel)
    return nil if boat_departure.blank?

    boat_time = boat_departure.in_time_zone(hotel.hotel_time_zone)
    {
      date: boat_time.strftime("%d %b %Y"),
      time: boat_time.strftime("%I:%M %p")
    }
  end
end
