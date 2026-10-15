# frozen_string_literal: true

module VendorDirectory
  OpeningHours = Data.define(:days, :opens, :closes) do
    DAY_INDEX = { "Sun" => 0, "Mon" => 1, "Tue" => 2, "Wed" => 3, "Thu" => 4, "Fri" => 5, "Sat" => 6 }.freeze

    def closed? = opens.to_s.casecmp?("closed")

    def label = closed? ? "Closed" : "#{opens} – #{closes}"

    # True when `time` falls inside this slot. Checked against every weekday
    # the slot covers, not only the one `time` itself falls on -- a
    # 16:00-01:00 Friday slot is still open at 00:30 Saturday, which a naive
    # "is today's weekday in range" check would miss entirely.
    def open_at?(time) = closes_at_for(time).present?

    # The moment *this* slot's currently-running window closes, or nil when
    # `time` doesn't fall inside one. Shared by open_at? (present? is enough
    # to answer "is it open") and by Vendor#closing_soon?, which needs the
    # actual moment to compare against.
    def closes_at_for(time)
      return nil if closed?

      day_range.each do |wday|
        anchor = time.to_date - ((time.wday - wday) % 7)
        opens_at = time.time_zone.local(anchor.year, anchor.month, anchor.day, open_hour, open_minute)
        closes_at = time.time_zone.local(anchor.year, anchor.month, anchor.day, close_hour, close_minute)
        closes_at += 1.day if closes_at <= opens_at

        return closes_at if time >= opens_at && time < closes_at
      end

      nil
    end

    # The next moment this slot opens after `time`, or nil if it never does
    # (a permanently "Closed" slot). Checks eight days out -- day_range
    # recurs weekly, so if today's own occurrence has already opened (or
    # today isn't covered at all) the next one is at most 7 days away.
    def next_open_after(time)
      return nil if closed?

      (0..7).each do |offset|
        day = time.to_date + offset
        next unless day_range.include?(day.wday)

        opens_at = time.time_zone.local(day.year, day.month, day.day, open_hour, open_minute)
        return opens_at if opens_at > time
      end

      nil
    end

    private

    # "Mon", "Mon – Fri", "Sun – Mon" (an explicit two-day closed slot) all
    # parse the same way; a range where the start sorts after the end (e.g.
    # a slot spanning Friday through Sunday) wraps around the week instead
    # of coming up empty.
    def day_range
      parts = days.to_s.split(/[–-]/).map(&:strip)
      start_day = DAY_INDEX.fetch(parts.first, 0)
      end_day = DAY_INDEX.fetch(parts.last, start_day)

      start_day <= end_day ? (start_day..end_day).to_a : ((start_day..6).to_a + (0..end_day).to_a)
    end

    def open_hour = opens.to_s.split(":").first.to_i
    def open_minute = opens.to_s.split(":").second.to_i
    def close_hour = closes.to_s.split(":").first.to_i
    def close_minute = closes.to_s.split(":").second.to_i
  end
end
