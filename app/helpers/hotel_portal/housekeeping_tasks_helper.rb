# frozen_string_literal: true

module HotelPortal
  module HousekeepingTasksHelper
    NONE_SELECTED = "__none__"

    # The filter header cells are data-turbo-permanent, so Turbo keeps the first
    # render of this badge. The housekeeping-table Stimulus controller reads the
    # data attributes and rewrites the label after each filter change.
    def housekeeping_filter_badge(name:, title:, noun:, selected:)
      values = Array(selected).map(&:to_s)
      count = housekeeping_filter_count(values)

      render PanelsUI::Badge.new(
        label: values.empty? ? "All" : count.to_s,
        variant: :primary,
        size: :xs,
        aria: { label: values.empty? ? "All #{noun}" : "#{count} #{noun} selected" },
        data: { housekeeping_filter_badge: name, housekeeping_filter_title: title,
                housekeeping_filter_noun: noun }
      )
    end

    def housekeeping_filter_aria(title:, selected:)
      values = Array(selected).map(&:to_s)
      state = values.empty? ? "all selected" : "#{housekeeping_filter_count(values)} selected"

      "Filter #{title}, #{state}"
    end

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

    private

    # An empty filter means every option is on. The none sentinel means no option
    # is on, and it must not count as one selected value.
    def housekeeping_filter_count(values)
      values.include?(NONE_SELECTED) ? 0 : values.size
    end
  end
end
