# frozen_string_literal: true

# What a guest sees for a booking or refund status: a word, a tone, and an
# icon. The guest never reads an internal status. "Due out detected" is still
# "Checked in" to them, and an overbooking is the property's problem, not
# theirs.
#
# The icon and the word carry the meaning; the tone only repeats it, so a
# guest who cannot see the tint still reads the whole status.
module Guest::StatusBadges
  Badge = Data.define(:label, :tone, :icon)

  BOOKING = {
    "pending" => Badge.new(label: "Pending", tone: :warning, icon: "clock"),
    "confirmed" => Badge.new(label: "Confirmed", tone: :info, icon: "calendar-check"),
    "checked_in" => Badge.new(label: "Checked in", tone: :success, icon: "door-open"),
    "completed" => Badge.new(label: "Completed", tone: :muted, icon: "circle-check"),
    "cancelled" => Badge.new(label: "Cancelled", tone: :destructive, icon: "circle-x"),
    "no_show" => Badge.new(label: "No-show", tone: :destructive, icon: "user-x")
  }.freeze

  # The booking statuses behind each guest status. The list filter reads this
  # too, so "Checked in" finds a guest who is due out today.
  BOOKING_GROUPS = {
    "pending" => %w[pending],
    "confirmed" => %w[confirmed no_show_detected overbooked],
    "checked_in" => Booking::IN_HOUSE_STATUSES,
    "completed" => %w[completed],
    "cancelled" => %w[cancelled voided],
    "no_show" => %w[no_show]
  }.freeze

  REFUND = {
    "pending" => Badge.new(label: "Pending", tone: :warning, icon: "clock"),
    "approved" => Badge.new(label: "Approved", tone: :info, icon: "badge-check"),
    "completed" => Badge.new(label: "Refunded", tone: :success, icon: "circle-check"),
    "rejected" => Badge.new(label: "Not approved", tone: :destructive, icon: "circle-x")
  }.freeze

  def self.booking_group(status)
    BOOKING_GROUPS.find { |_, statuses| statuses.include?(status.to_s) }&.first
  end

  def self.booking(status)
    BOOKING.fetch(booking_group(status)) { unknown(status) }
  end

  def self.refund(status)
    REFUND.fetch(status.to_s) { unknown(status) }
  end

  def self.unknown(status) = Badge.new(label: status.to_s.humanize, tone: :muted, icon: "circle-question-mark")
end
