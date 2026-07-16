# frozen_string_literal: true

module StayView
  class BoardState
    DENSITIES = %i[compact comfortable].freeze
    FILTER_KEYS = %i[room_type_id booking_status occupancy physical_status].freeze

    attr_reader :date_window, :density, :filters

    def initialize(hotel:, params:, now: Time.current)
      source = params.to_h.with_indifferent_access
      view_mode = source[:view].to_s.presence_in(DateWindow::VIEW_MODES.map(&:to_s)) || "timeline"
      start_date = view_mode == "rooms" ? source[:date] : source[:start_date]

      @date_window = DateWindow.new(hotel:, start_date:, days: source[:days], view_mode:, now:)
      @density = source[:density].to_s.to_sym
      @density = :compact unless DENSITIES.include?(@density)
      @filters = FilterState.build(source.slice(*FILTER_KEYS))
      freeze
    end

    def view_mode = date_window.view_mode

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

    private

    def base_query
      dates = if view_mode == :rooms
        { view: :rooms, date: date_window.start_date }
      else
        { view: :timeline, start_date: date_window.start_date, days: date_window.days }
      end

      dates.merge(filters.to_h.compact).merge(density: density)
    end

    def normalize_query(values)
      view = values[:view].to_s == "rooms" ? :rooms : :timeline
      normalized = values.slice(*FILTER_KEYS, :density).compact
      normalized[:density] = normalized[:density].to_s.presence_in(DENSITIES.map(&:to_s)) || density

      if view == :rooms
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
