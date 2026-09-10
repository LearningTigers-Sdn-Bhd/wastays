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
    def open_at?(time)
      return false if closed?

      day_range.any? do |wday|
        anchor = time.to_date - ((time.wday - wday) % 7)
        opens_at = time.time_zone.local(anchor.year, anchor.month, anchor.day, open_hour, open_minute)
        closes_at = time.time_zone.local(anchor.year, anchor.month, anchor.day, close_hour, close_minute)
        closes_at += 1.day if closes_at <= opens_at

        time >= opens_at && time < closes_at
      end
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
