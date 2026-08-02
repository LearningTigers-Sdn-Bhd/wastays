# frozen_string_literal: true

module HotelPortal
  module HousekeepingTasksHelper
    def housekeeping_hidden_board_filters(filters)
      safe_join(filters.flat_map do |key, value|
        if value.is_a?(Array)
          value.map { |item| hidden_field_tag "filters[#{key}][]", item, id: nil }
        else
          [ hidden_field_tag("filters[#{key}]", value, id: nil) ]
        end
      end)
    end

    def housekeeping_sort_direction(key)
      return unless params[:sort].to_s == key

      params[:direction].to_s == "desc" ? "desc" : "asc"
    end

    def housekeeping_sort_path(key)
      next_direction = housekeeping_sort_direction(key) == "asc" ? "desc" : "asc"
      hotel_housekeeping_tasks_path(current_hotel, board_filters.merge(sort: key, direction: next_direction))
    end

    def housekeeping_sort_aria(key)
      direction = housekeeping_sort_direction(key)
      return "none" unless direction

      direction == "asc" ? "ascending" : "descending"
    end
  end
end
