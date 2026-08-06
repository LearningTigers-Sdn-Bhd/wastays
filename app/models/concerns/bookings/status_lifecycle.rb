# frozen_string_literal: true

module Bookings
  module StatusLifecycle
    EVENTS = {
      "pending" => {
        "confirm" => "confirmed",
        "cancel" => "cancelled",
        "void" => "voided"
      },
      "confirmed" => {
        "check_in" => "checked_in",
        "cancel" => "cancelled",
        "detect_no_show" => "no_show_detected",
        "mark_overbooked" => "overbooked",
        "void" => "voided"
      },
      "no_show_detected" => {
        "backdated_check_in" => "checked_in",
        "mark_no_show" => "no_show",
        "auto_mark_no_show" => "no_show",
        "cancel" => "cancelled",
        "void" => "voided"
      },
      "overbooked" => {
        "resolve_overbooking" => "confirmed",
        "cancel" => "cancelled",
        "void" => "voided"
      },
      "checked_in" => {
        "check_out" => "completed",
        "detect_due_out" => "due_out_detected",
        "undo_check_in" => "confirmed",
        "void" => "voided"
      },
      "due_out_detected" => {
        "resolve_late_checkout" => "checked_in",
        "reject_late_checkout" => "checkout_required",
        "void" => "voided"
      },
      "checkout_required" => {
        "check_out" => "completed",
        "void" => "voided"
      },
      "no_show" => {
        "reinstate" => "checked_in",
        "void" => "voided"
      },
      "cancelled" => { "void" => "voided" },
      "completed" => { "void" => "voided" },
      "voided" => {}
    }.freeze

    TERMINAL_STATUSES = %w[cancelled completed voided].freeze

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
