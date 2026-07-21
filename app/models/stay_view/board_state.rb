# frozen_string_literal: true

module StayView
  class BoardState
    FILTER_KEYS = %i[room_type_id rate_plan_id occupancy physical_status room_state].freeze
    GROUPINGS = %w[room_type none].freeze
    DEFAULT_GROUPING = "room_type"

    attr_reader :date_window, :filters, :room_grouping

    def initialize(hotel:, params:, now: Time.current)
      source = params.to_h.with_indifferent_access
      view_mode = source[:view].to_s.presence_in(DateWindow::VIEW_MODES.map(&:to_s)) || "timeline"
      start_date = view_mode == "rooms" ? source[:date] : source[:start_date]

      @date_window = DateWindow.new(hotel:, start_date:, days: source[:days], view_mode:, now:)
      @filters = FilterState.build(source.slice(*FILTER_KEYS)).for_view(view_mode)
      @room_grouping = source[:group_by].to_s.presence_in(GROUPINGS) || DEFAULT_GROUPING
      @hotel = hotel
      @now = now
      freeze
    end

    def view_mode = date_window.view_mode
    def density = :compact
    def grouped_rooms? = room_grouping == "room_type"

    def build_options
      {
        start_date: date_window.start_date,
        days: date_window.days,
        view_mode:,
        filters: filters.to_h.compact
      }
    end

    def query(overrides = {})
      values = base_query.merge(overrides.to_h.symbolize_keys)
      normalize_query(values)
    end

    def return_path(hotel)
      Rails.application.routes.url_helpers.hotel_stay_view_path(hotel, query)
    end

    def with_filters(effective_filters)
      cleared_filters = FILTER_KEYS.index_with(nil)
      self.class.new(
        hotel: @hotel,
        params: query(cleared_filters.merge(effective_filters.to_h.compact)),
        now: @now
      )
    end

    private

    def base_query
      dates = if view_mode == :rooms
        { view: :rooms, date: date_window.start_date, group_by: room_grouping }
      else
        { view: :timeline, start_date: date_window.start_date, days: date_window.days }
      end

      dates.merge(filters.to_h.compact)
    end

    def normalize_query(values)
      view = values[:view].to_s == "rooms" ? :rooms : :timeline
      normalized = values.slice(*FILTER_KEYS).compact
      view == :rooms ? normalized.delete(:occupancy) : normalized.delete(:room_state)

      if view == :rooms
        grouping = values[:group_by].to_s.presence_in(GROUPINGS)
        normalized[:group_by] = grouping if grouping && grouping != DEFAULT_GROUPING
        normalized.merge(view:, date: values[:date].presence || values[:start_date].presence || date_window.start_date)
      else
        normalized.merge(
          view:,
          start_date: values[:start_date].presence || values[:date].presence || date_window.start_date,
          days: Integer(values[:days], exception: false).presence_in(DateWindow::ALLOWED_DAYS) || DateWindow::DEFAULT_DAYS
        )
      end
    end
  end
end
