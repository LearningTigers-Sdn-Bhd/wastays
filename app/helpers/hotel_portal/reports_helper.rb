# frozen_string_literal: true

module HotelPortal::ReportsHelper
  def report_rows_grouped_by_month(rows, date_preset:, &date_for)
    return { nil => rows } unless date_preset == "this_year"

    rows.group_by { |row| date_for.call(row).to_date.beginning_of_month }
  end

  def daily_report_adjustment_presentation(amount)
    amount = amount.to_d
    if amount.positive?
      { value: "+ MYR #{number_with_precision(amount, precision: 2, delimiter: ",")}", detail: "Increases revenue", variant: :success }
    elsif amount.negative?
      { value: "- MYR #{number_with_precision(amount.abs, precision: 2, delimiter: ",")}", detail: "Reduces revenue", variant: :destructive }
    else
      { value: "MYR 0.00", detail: "No revenue adjustment", variant: :neutral }
    end
  end

  def report_amount(value)
    value.to_d.zero? ? "0" : number_with_precision(value, precision: 2, delimiter: ",")
  end

  def daily_revenue_cell(value, hotel:, date:, category:, date_preset:, negative: false)
    amount = value.to_d
    sign = negative && !amount.zero? ? "- " : ""
    text = "#{sign}MYR #{report_amount(amount)}"
    return text if amount.zero?

    link_to text,
      daily_revenue_cell_hotel_reports_path(hotel, date: date.iso8601, category: category, date_preset: date_preset),
      class: "underline decoration-dotted decoration-slate-300 underline-offset-2 hover:decoration-slate-600",
      data: { turbo_frame: "offcanvas_drawer", offcanvas_variant: "right" }
  end

  def guest_reports_date_range_label(report)
    if report.start_date == report.end_date
      report.start_date.strftime("%A, %d %b %Y")
    else
      "#{report.start_date.strftime('%d %b %Y')} - #{report.end_date.strftime('%d %b %Y')}"
    end
  end

  # Every report is passed in already built. Running one here would mean the
  # tab strip re-querying on every tab just to put a number on a badge.
  def guest_report_tabs_data(report:, bibo_report:, police_report:, meal_prep_report:, active_tab:, grc_total_count:, current_hotel:, date_preset:)
    tabs = [
      { label: "Arrivals", value: "arrivals", count: report.arrival_count },
      { label: "In-House", value: "in_house", count: report.in_house_count },
      { label: "Departures", value: "departures", count: report.departure_count },
      { label: "Checkout", value: "checkout", count: report.checkout_count },
      { label: "Police report", value: "police_report", count: police_report.rows.size },
      { label: "Registration Cards", value: "registration_cards", count: grc_total_count }
    ]

    if current_hotel.allow_boat_information?
      tabs << { label: "Boat Transfers", value: "bibo", count: bibo_report ? (bibo_report.boat_in_count + bibo_report.boat_out_count) : 0 }
      tabs << { label: "Meal Prep", value: "meal_prep", count: meal_prep_report&.records&.size.to_i }
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
    !%w[registration_cards police_report bibo meal_prep].include?(active_tab)
  end

  def format_report_boat_time(boat_departure, hotel)
    return nil if boat_departure.blank?

    boat_time = boat_departure.in_time_zone(hotel.hotel_time_zone)
    {
      date: boat_time.strftime("%d %b %Y"),
      time: boat_time.strftime("%I:%M %p")
    }
  end

  def show_guest_report_export?(active_tab)
    feature_enabled_for_hotel?("excel_pdf_export") && active_tab != "registration_cards"
  end

  def custom_date_range_class(date_preset)
    [ "custom", "single" ].include?(date_preset) ? "flex" : "hidden"
  end

  def end_date_container_class(date_preset)
    date_preset == "single" ? "hidden" : ""
  end

  def guest_report_tab_class(tab)
    base = "inline-flex h-10 items-center gap-2 whitespace-nowrap rounded-xl border px-4 text-sm font-semibold transition"
    if tab[:active]
      "#{base} border-blue-600 bg-blue-600 text-white shadow-sm"
    else
      "#{base} border-slate-200 bg-white text-slate-700 hover:border-slate-300 hover:bg-slate-50"
    end
  end

  def guest_report_tab_count_class(tab)
    base = "rounded-full px-1.5 py-0.5 text-[10px] font-bold"
    if tab[:active]
      "#{base} bg-white/20 text-white"
    else
      "#{base} bg-slate-100 text-slate-500"
    end
  end

  def meal_prep_display_meals(meal_type_string, selected_meal_type)
    meals = meal_type_string.to_s.split(", ")
    if selected_meal_type.present?
      meals = meals.select { |m| m.casecmp?(selected_meal_type) }
    end
    meals
  end

  def meal_prep_color_class(meal)
    case meal.downcase
    when "breakfast" then "text-[#b45309]"
    when "lunch" then "text-[#15803d]"
    when "dinner" then "text-[#c2410c]"
    else "text-slate-700"
    end
  end

  def bibo_sections(report)
    HotelPortal::Reports::BiboReport::LEGS.map do |leg|
      leg.merge(rows: report.public_send(leg[:rows_key]))
    end
  end

  def bibo_row_class(index)
    base = "align-top transition-colors print:bg-white"
    if index.even?
      "#{base} bg-white"
    else
      "#{base} bg-slate-50/55"
    end
  end

  def arrivals_departures_row_class(index)
    base = "align-top transition-colors print:bg-white"
    if index.even?
      "#{base} bg-white"
    else
      "#{base} bg-slate-50/55"
    end
  end

  def arrivals_departures_boat_time(row, type, hotel)
    boat_val = (type == :arrival ? row[:boat_arrival] : row[:boat_departure])
    return nil if boat_val.blank?

    format_report_boat_time(boat_val, hotel)
  end

  def display_latest_note(note)
    note.presence || "-"
  end
end
