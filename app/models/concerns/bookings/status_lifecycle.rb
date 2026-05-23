# frozen_string_literal: true

module Bookings
  module StatusLifecycle
    EVENTS = {
      "pending" => {
        "confirm" => "confirmed",
        "cancel" => "cancelled"
      },
      "confirmed" => {
        "check_in" => "checked_in",
        "cancel" => "cancelled",
        "mark_no_show" => "no_show",
        "mark_overbooked" => "overbooked"
      },
      "overbooked" => {
        "resolve_overbooking" => "confirmed",
        "cancel" => "cancelled"
      },
      "checked_in" => {
        "check_out" => "completed",
        "detect_late_checkout" => "review_due_out"
      },
      "review_due_out" => {
        "check_out" => "completed",
        "resolve_late_checkout" => "checked_in"
      },
      "no_show" => {
        "reinstate" => "checked_in"
      },
      "cancelled" => {},
      "completed" => {}
    }.freeze

    TERMINAL_STATUSES = %w[cancelled completed].freeze

    module_function

    def valid_transition?(from:, to:, event:)
      EVENTS.dig(from.to_s, event.to_s) == to.to_s
    end

    def terminal_status?(status)
      TERMINAL_STATUSES.include?(status.to_s)
    end

    def transition_error(from:, to:, event:)
      from = from.to_s
      to = to.to_s
      event = event.to_s

      return "#{from} is a terminal status" if terminal_status?(from)
      return "status transition event is required" if event.blank?

      "cannot transition from #{from} to #{to} with event #{event}"
    end
  end
end
