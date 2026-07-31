# frozen_string_literal: true

module HotelPortal
  module Requests
    # The stretch of time the requests board is looking at.
    #
    # StayView::DateWindow looks forward from a date because it is about rooms
    # still to be filled. This one looks back, because it is about work already
    # asked for: the date picked is the newest day on the board and the range is
    # how far behind it to reach.
    #
    # The board's columns read timestamps, not dates, so the window hands out
    # times in the hotel's own zone. Comparing a datetime column against a bare
    # date compares it against midnight UTC, which moves the boundary for every
    # hotel that does not happen to keep UTC hours.
    #
    # It governs the lanes that grow without end -- Completed and Archived -- and
    # not the open ones. It used to bound every lane, which meant a short range
    # turned an inbox into a keyhole: open work older than the widest range could
    # not be reached at all, and the board could only say how much of it there
    # was. Open work is self-limiting because staff clear it, so it needs no
    # range; finished work needs one, and can now have a short one.
    class DateWindow
      ALLOWED_DAYS = [ 1, 3, 5, 7 ].freeze
      DEFAULT_DAYS = 7

      attr_reader :today, :anchor_date, :start_date, :end_date, :days, :time_zone_name

      def initialize(hotel:, anchor_date: nil, days: nil, now: Time.current)
        zone = hotel.hotel_time_zone
        @time_zone_name = zone.name.freeze
        @days = normalize_days(days)
        # The wall clock, deliberately, and not the hotel's business date. A
        # business date waiting on a night audit sits in the past, and a window
        # reaching back from it would end before the requests arriving now --
        # hiding today's work on a board whose whole job is to show it. Stay
        # View can anchor on the business date because it looks forward.
        @today = now.in_time_zone(zone).to_date
        @anchor_date = parse_date(anchor_date) || @today
        # The anchor is a day the board shows, not the edge it stops at.
        @end_date = @anchor_date + 1
        @start_date = @end_date - @days
        freeze
      end

      # The window as the timestamps a column is compared against: from the
      # first day's opening moment up to, but not including, the moment the day
      # after the anchor begins.
      def range
        starts_at...ends_at
      end

      def starts_at
        zone.local(start_date.year, start_date.month, start_date.day)
      end

      def ends_at
        zone.local(end_date.year, end_date.month, end_date.day)
      end

      def include?(date)
        date = date.to_date
        start_date <= date && date < end_date
      end

      def previous
        shifted(anchor_date - days)
      end

      def next
        shifted(anchor_date + days)
      end

      def today?
        anchor_date == today
      end

      # The same range, ending today.
      def at_today
        shifted(today)
      end

      # How the window travels in a link.
      def query_params
        { date: anchor_date.iso8601, days: days }
      end

      private

      def shifted(new_anchor_date, days: @days)
        copy = dup
        copy.instance_variable_set(:@days, days)
        copy.instance_variable_set(:@anchor_date, new_anchor_date)
        copy.instance_variable_set(:@end_date, new_anchor_date + 1)
        copy.instance_variable_set(:@start_date, new_anchor_date + 1 - days)
        copy.freeze
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

      def zone
        Time.find_zone!(time_zone_name)
      end
    end
  end
end
