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
