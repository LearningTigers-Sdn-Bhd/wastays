# frozen_string_literal: true

module StayView
  class DateWindow
    ALLOWED_DAYS = [ 7, 14, 21, 30 ].freeze
    DEFAULT_DAYS = 14
    VIEW_MODES = %i[timeline rooms].freeze

    attr_reader :today, :operational_date, :start_date, :end_date, :days, :view_mode, :time_zone_name

    def initialize(hotel:, start_date: nil, days: nil, view_mode: :timeline, now: Time.current)
      zone = hotel.hotel_time_zone
      @today = now.in_time_zone(zone).to_date
      @operational_date = hotel.current_business_date || hotel.business_date_for(now)
      @view_mode = normalize_view_mode(view_mode)
      @days = @view_mode == :rooms ? 1 : normalize_days(days)
      @start_date = parse_date(start_date) || @operational_date
      @end_date = @start_date + @days.days
      @time_zone_name = zone.name.freeze
      freeze
    end

    def dates
      (start_date...end_date).to_a.freeze
    end

    def previous
      shifted(start_date - days.days)
    end

    def next
      shifted(end_date)
    end

    def include?(date)
      date = date.to_date
      start_date <= date && date < end_date
    end

    def overlap?(range_start, range_end)
      range_start.to_date < end_date && range_end.to_date > start_date
    end

    def clip(range_start, range_end)
      [ [ range_start.to_date, start_date ].max, [ range_end.to_date, end_date ].min ].freeze
    end

    def booking_tracks(check_in, check_out)
      start_on = check_in.to_date
      end_on = check_out.to_date
      TrackRange.new(
        start_track: start_on < start_date ? 1 : centre_track(start_on),
        end_track: end_on >= end_date ? final_track : centre_track(end_on),
        clipped_left: start_on < start_date,
        clipped_right: end_on >= end_date
      )
    end

    def full_day_tracks(first_date, exclusive_last_date)
      start_on = first_date.to_date
      end_on = exclusive_last_date.to_date
      TrackRange.new(
        start_track: start_on < start_date ? 1 : boundary_track(start_on),
        end_track: end_on >= end_date ? final_track : boundary_track(end_on),
        clipped_left: start_on < start_date,
        clipped_right: end_on > end_date
      )
    end

    def window_start_at
      zone.local(start_date.year, start_date.month, start_date.day)
    end

    def window_end_at
      zone.local(end_date.year, end_date.month, end_date.day)
    end

    private

    def shifted(new_start_date)
      copy = dup
      copy.instance_variable_set(:@start_date, new_start_date)
      copy.instance_variable_set(:@end_date, new_start_date + days.days)
      copy.freeze
    end

    def normalize_view_mode(value)
      candidate = value.to_s.to_sym
      VIEW_MODES.include?(candidate) ? candidate : :timeline
    end

    def normalize_days(value)
      candidate = Integer(value, exception: false)
      ALLOWED_DAYS.include?(candidate) ? candidate : DEFAULT_DAYS
    end

    def parse_date(value)
      return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)
      return if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def centre_track(date)
      ((date - start_date).to_i * 2) + 2
    end

    def boundary_track(date)
      ((date - start_date).to_i * 2) + 1
    end

    def final_track
      (days * 2) + 1
    end

    def zone
      Time.find_zone!(time_zone_name)
    end
  end
end
