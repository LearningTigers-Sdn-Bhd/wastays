# frozen_string_literal: true

module HotelPortal
  module InventoryDashboardsHelper
    def inventory_calendar_base_params(start_date:, view_currencies:, selected_room_type_id:)
      {
        start_date: start_date,
        view_currencies: view_currencies,
        room_type_id: selected_room_type_id
      }.compact
    end

    def inventory_navigation_state(room_type_id:, view_currencies:, display_currency:, active_tab:, active_subtab:, range_mode:, days:, month:)
      {
        view_currencies: view_currencies,
        display_currency: display_currency,
        room_type_id: room_type_id,
        tab: active_tab,
        subtab: active_subtab,
        days: range_mode == "month" ? "month" : days,
        month: range_mode == "month" ? inventory_month_param(month) : nil
      }.compact
    end

    def inventory_last_synced_at_label(time = Time.current)
      time.strftime("%-I:%M %p")
    end

    def inventory_month_param(date)
      date.strftime("%Y-%m")
    end

    def inventory_month_label(date)
      date.strftime("%B %Y")
    end

    def inventory_date_range_label(start_date, end_date)
      "#{start_date.strftime('%b %-d')} – #{end_date.strftime('%b %-d, %Y')}"
    end

    def inventory_date_header_parts(date)
      {
        day: date.strftime("%a"),
        num: date.strftime("%d"),
        month: date.strftime("%b")
      }
    end

    def inventory_calendar_currencies
      CurrencyCatalog::COMMON_CODES
    end

    def inventory_currency_options
      CurrencyCatalog.options
    end

    def inventory_parent_row?(row)
      row.inventory_row?
    end

    def inventory_parent_room_type_id_for(row)
      return if inventory_parent_row?(row)

      row.room_type_id
    end

    def inventory_calendar_cell(calendar, row, date)
      calendar.cell_for(row, date)
    end

    # A rate plan can be assigned to several room categories, so the calendar's
    # per-category option list repeats one plan under each of them. Those repeats
    # share a value, which in a single <select> means the first label wins — an
    # Executive Penthouse cell would show its plan as "Ocean Villa King - …".
    # Collapse them: the room category is chosen in its own field, so the plan
    # only needs its own name. Tiers keep the category, being category-specific.
    def inventory_rate_plan_choices(calendar)
      calendar.rate_plan_options_struct.each_with_object([]) do |option, choices|
        next if choices.any? { |_label, value| value == option.id.to_s }

        label = option.kind == :tier ? option.label : option.label.split(" - ", 2).last
        choices << [ label, option.id.to_s ]
      end
    end

    def inventory_weekday_options
      [
        [ "Mon", 1 ],
        [ "Tue", 2 ],
        [ "Wed", 3 ],
        [ "Thu", 4 ],
        [ "Fri", 5 ],
        [ "Sat", 6 ],
        [ "Sun", 0 ]
      ]
    end
  end
end
