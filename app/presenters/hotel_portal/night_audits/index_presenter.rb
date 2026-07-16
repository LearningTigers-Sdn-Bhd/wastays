# frozen_string_literal: true

module HotelPortal
  module NightAudits
    class IndexPresenter
    DateTile = Struct.new(:label, :value, :detail, keyword_init: true)
    Counter = Struct.new(:label, :value, :tone, :detail, keyword_init: true)
    Group = Struct.new(:key, :label, :count, :rows, :tone, keyword_init: true)
    ReadinessRow = Struct.new(:type, :count, :summary, :tone, :action, :booking_id, keyword_init: true)
    BlockerRow = Struct.new(:type, :reason, :detail, :action, :booking_id, keyword_init: true)
    Action = Struct.new(:label, :enabled, :disabled_reason, :url, :method, :night_audit, keyword_init: true)
    HistoryRow = Struct.new(
      :night_audit,
      :business_date,
      :status_label,
      :status_class,
      :trigger_label,
      :performed_by,
      :finished_at,
      :exceptional?,
      keyword_init: true
    )

    attr_reader :hotel, :current_user, :business_date_record, :evaluation, :night_audits

    def initialize(hotel:, current_user:, business_date_record:, evaluation:, night_audits:)
      @hotel = hotel
      @current_user = current_user
      @business_date_record = business_date_record
      @evaluation = evaluation || {}
      @night_audits = night_audits
    end

    def ui_state
      return "OPEN" unless business_date_record
      return "AUDIT_RUNNING" if business_date_record.audit_running?
      return "AUDIT_FAILED" if last_attempt&.failed?
      return "AUDIT_BLOCKED" if business_date_record.audit_blocked?
      return "FORCE_CLOSED" if business_date_record.force_closed?
      return "CLOSED" if business_date_record.closed?
      return retry_state_label if retry_available?
      return "READY_FOR_AUDIT" if ready_for_audit?

      "OPEN"
    end

    def page_title
      "Business Date Control Center"
    end

    def page_subtitle
      "Night Audit closes the hotel's accounting business date, not the calendar date."
    end

    def business_date
      business_date_record&.business_date || hotel.current_business_date
    end

    def next_business_date
      business_date&.+(1.day)
    end

    def current_business_date_label
      format_date(business_date)
    end

    def calendar_date
      hotel.hotel_time_zone.today
    end

    def calendar_date_label
      format_date(calendar_date)
    end

    def hotel_timezone_label
      hotel.hotel_time_zone.name
    end

    def date_tiles
      [
        DateTile.new(label: "Current Business Date", value: current_business_date_label, detail: "Authoritative audit target"),
        DateTile.new(label: "Calendar Date", value: calendar_date_label, detail: hotel.hotel_time_zone.name)
      ]
    end

    def date_difference?
      business_date.present? && business_date != calendar_date
    end

    def date_explanation
      if date_difference?
        "Calendar date is #{calendar_date_label}, but the hotel remains on business date #{current_business_date_label} until #{current_business_date_label} closes successfully."
      else
        "Business date and calendar date currently match. The audit target still comes from the hotel business date record."
      end
    end

    def status_label
      case ui_state
      when "READY_FOR_AUDIT" then retry_available? ? "Retry Available" : "Ready for Audit"
      when "AUDIT_RUNNING" then "Audit Running"
      when "AUDIT_BLOCKED" then "Audit Blocked"
      when "AUDIT_FAILED" then retry_available? ? "Audit Can Be Retried" : "Audit Failed"
      when "CLOSED" then "Closed"
      when "FORCE_CLOSED" then "Force Closed"
      else "Open"
      end
    end

    def status_badge_class
      case ui_state
      when "READY_FOR_AUDIT" then "border-emerald-200 bg-emerald-50 text-emerald-700"
      when "AUDIT_RUNNING" then "border-sky-200 bg-sky-50 text-sky-700"
      when "AUDIT_BLOCKED" then "border-amber-200 bg-amber-50 text-amber-700"
      when "AUDIT_FAILED" then "border-red-200 bg-red-50 text-red-700"
      when "CLOSED" then "border-border bg-muted text-foreground"
      when "FORCE_CLOSED" then "border-red-300 bg-red-50 text-red-800"
      else "border-border bg-card text-foreground"
      end
    end

    def business_date_status_label
      business_date_record&.status&.humanize || "Not initialized"
    end

    def business_date_status_badge_class
      case business_date_record&.status
      when "open" then "border-blue-200 bg-blue-50 text-blue-700"
      when "audit_running" then "border-sky-200 bg-sky-50 text-sky-700"
      when "audit_blocked" then "border-amber-200 bg-amber-50 text-amber-700"
      when "closed" then "border-emerald-200 bg-emerald-50 text-emerald-700"
      when "force_closed" then "border-red-300 bg-red-50 text-red-800"
      else "border-border bg-muted text-muted-foreground"
      end
    end

    def main_message
      case ui_state
      when "READY_FOR_AUDIT"
        "#{current_business_date_label} is ready to close. After a successful audit, the hotel business date will advance to #{format_date(next_business_date)}."
      when "AUDIT_RUNNING"
        "Night Audit is running for business date #{current_business_date_label}. The hotel remains on this business date until the run finishes and closes successfully."
      when "AUDIT_BLOCKED"
        "Business date #{current_business_date_label} cannot close yet. Resolve blockers, then retry. The hotel remains on #{current_business_date_label} until closure succeeds."
      when "AUDIT_FAILED"
        "The last audit attempt failed for #{current_business_date_label}. Review the failure and retry when the issue is resolved."
      when "FORCE_CLOSED"
        "#{current_business_date_label} was force-closed by override. Review unresolved blockers and audit events before relying on financial totals."
      when "CLOSED"
        "#{current_business_date_label} is closed. The control center should now focus on the next current business date."
      else
        "The hotel is still operating on business date #{current_business_date_label}. Calendar date is #{calendar_date_label}, but #{current_business_date_label} has not closed yet."
      end
    end

    def readiness_counters
      [
        Counter.new(label: "Blockers", value: blocker_count, tone: blocker_count.positive? ? "danger" : "neutral", detail: "Must be resolved before clean close"),
        Counter.new(label: "Warnings", value: warning_count, tone: warning_count.positive? ? "warning" : "neutral", detail: "Non-blocking exceptions"),
        Counter.new(label: "Arrivals", value: summary_value("arrivals_count"), tone: "neutral", detail: "Current snapshot"),
        Counter.new(label: "Due Outs", value: summary_value("due_out_count"), tone: "neutral", detail: "Current snapshot"),
        Counter.new(label: "Review Queue", value: review_queue_value, tone: "neutral", detail: "Arrival / due-out")
      ]
    end

    def review_queue_value
      "#{arrival_review_summary[:value]} / #{due_out_review_summary[:value]}"
    end

    def blocker_groups
      grouped_rows(blocked_details, "danger")
    end

    def warning_groups
      grouped_rows(exceptions, "warning")
    end

    def arrival_review_summary
      {
        label: "Arrival Review",
        value: summary_value("review_no_show_count"),
        detail: "Current review-no-show snapshot. TODO: expose run-specific moved count when available."
      }
    end

    def due_out_review_summary
      {
        label: "Due-Out Review",
        value: exceptions.fetch("review_due_out", []).count,
        detail: "Bookings waiting in due-out review."
      }
    end

    def readiness_detail_rows
      blocker_rows = blocker_groups.map { |group| readiness_group_row(group) }
      warning_rows = warning_groups.map { |group| readiness_group_row(group) }

      blocker_rows + warning_rows + [
        ReadinessRow.new(
          type: arrival_review_summary[:label],
          count: arrival_review_summary[:value],
          summary: arrival_review_summary[:detail],
          tone: "neutral"
        ),
        ReadinessRow.new(
          type: due_out_review_summary[:label],
          count: due_out_review_summary[:value],
          summary: due_out_review_summary[:detail],
          tone: "neutral"
        )
      ]
    end

    def flattened_blocker_rows
      blocker_groups.flat_map do |group|
        group.rows.map do |row|
          BlockerRow.new(
            type: group.label,
            reason: row_detail(row, "reason", group.label),
            detail: blocker_item_detail(row),
            action: resolve_action.present? ? "resolve" : (row_booking_id(row).present? ? "booking" : nil),
            booking_id: row_booking_id(row)
          )
        end
      end
    end

    def last_attempt_summary
      return nil unless last_attempt

      {
        status: last_attempt_status_label,
        trigger: last_attempt.trigger_mode.to_s.humanize,
        performed_by: last_attempt.performed_by_user&.name || "System",
        started_at: format_datetime(last_attempt.started_at),
        finished_at: finished_at_label(last_attempt),
        notes: last_attempt.notes.presence,
        failure: failure_summary
      }
    end

    def primary_action
      return Action.new(label: "Refresh Status", enabled: true, night_audit: last_attempt) if running_attempt?
      return Action.new(label: "View Failure Details", enabled: true, night_audit: last_attempt) if last_attempt&.failed? && !retry_available?
      return Action.new(label: "Retry Audit", enabled: can_submit_audit?, disabled_reason: primary_disabled_reason) if retry_available?

      Action.new(label: "Run Audit", enabled: can_submit_audit?, disabled_reason: primary_disabled_reason)
    end

    def resolve_action
      return nil unless last_attempt&.blocked?

      Action.new(label: "Resolve Blockers", enabled: true, night_audit: last_attempt)
    end

    def danger_zone_visible?
      can_force_close? || force_close_unavailable_reason.present?
    end

    def can_force_close?
      force_close_permission? && force_close_eligible?
    end

    def force_close_permission?
      current_user.has_permission?("override_financial_date_lock", hotel: hotel)
    end

    def force_close_eligible?
      return false unless business_date_record

      business_date_record.audit_blocked? || business_date_record.audit_running? || last_attempt&.failed? || blocker_count.positive?
    end

    def force_close_unavailable_reason
      return "Only users with override permission can force close a business date." unless force_close_permission?
      return nil if force_close_eligible?

      "Force close is available only for blocked, failed, running, or blocker-heavy audit states."
    end

    def force_close_confirmation
      "Force Close Business Date warning: this will advance the hotel business date from #{current_business_date_label} to #{format_date(next_business_date)} without resolving all blockers. A reason is required. Continue?"
    end

    def history_rows
      night_audits.map do |night_audit|
        HistoryRow.new(
          night_audit: night_audit,
          business_date: format_date(night_audit.business_date),
          status_label: history_status_label(night_audit),
          status_class: history_status_class(night_audit),
          trigger_label: night_audit.trigger_mode.to_s.humanize,
          performed_by: night_audit.performed_by_user&.name || "System",
          finished_at: finished_at_label(night_audit),
          exceptional?: night_audit.failed? || night_audit.blocked? || night_audit.force_closed?
        )
      end
    end

    def format_date(date)
      date&.strftime("%d %b %Y") || "Not available"
    end

    def form_business_date_value
      business_date&.to_s
    end

    private

    def ready_for_audit?
      business_date_record&.open? && blocker_count.zero? && can_audit_now?
    end

    def retry_available?
      last_attempt.present? && (last_attempt.failed? || last_attempt.blocked?) && !running_attempt?
    end

    def retry_state_label
      retry_available? ? "READY_FOR_AUDIT" : "OPEN"
    end

    def can_submit_audit?
      return false unless business_date_record&.current?
      return false if running_attempt?
      return false if last_attempt&.completed?

      true
    end

    def primary_disabled_reason
      return "No current hotel business date has been initialized." unless business_date_record
      return "Night Audit is already scheduled or running for this business date." if running_attempt?
      return "This business date has already closed." if last_attempt&.completed?

      nil
    end

    def can_audit_now?
      business_date.present? && hotel.can_audit_date?(business_date)
    end

    def running_attempt?
      last_attempt.present? && (last_attempt.pending? || last_attempt.running?)
    end

    def last_attempt
      @last_attempt ||= hotel.night_audits.where(business_date: business_date).order(created_at: :desc).first if business_date
    end

    def last_attempt_status_label
      return "Force Closed" if last_attempt.force_closed?
      return "Audit Can Be Retried" if last_attempt.failed? || last_attempt.blocked?

      last_attempt.status.to_s.humanize
    end

    def blocked_details
      evaluation.fetch(:blocked_details, {}) || {}
    end

    def exceptions
      evaluation.fetch(:exceptions, {}) || {}
    end

    def summary
      evaluation.fetch(:summary, {}) || {}
    end

    def summary_value(key)
      summary.fetch(key, 0) || 0
    end

    def blocker_count
      @blocker_count ||= grouped_count(blocked_details)
    end

    def warning_count
      @warning_count ||= grouped_count(exceptions)
    end

    def grouped_count(groups)
      groups.values.flatten.count
    end

    def grouped_rows(groups, tone)
      groups.filter_map do |key, rows|
        next if rows.blank?

        Group.new(key: key, label: group_label(key), count: rows.count, rows: rows, tone: tone)
      end
    end

    def readiness_group_row(group)
      first_row = group.rows.first
      ReadinessRow.new(
        type: group.label,
        count: group.count,
        summary: readiness_group_summary(group),
        tone: group.tone,
        action: group.tone == "danger" && resolve_action.present? ? "resolve" : (row_booking_id(first_row).present? ? "booking" : nil),
        booking_id: row_booking_id(first_row)
      )
    end

    def row_booking_id(row)
      row.is_a?(Hash) ? row["booking_id"] : nil
    end

    def readiness_group_summary(group)
      item_label = "item".pluralize(group.count)
      return "#{group.count} #{item_label} requiring attention before close." if group.tone == "danger"

      "#{group.count} non-blocking review #{item_label}."
    end

    def row_detail(row, key, fallback)
      return fallback unless row.is_a?(Hash)

      row[key].presence || fallback
    end

    def blocker_item_detail(row)
      return "Operational blocker requires review." unless row.is_a?(Hash)

      [ row["guest_name"], row["confirmation_token"], row["status"]&.to_s&.humanize ].compact_blank.join(" · ").presence ||
        "Operational blocker requires review."
    end

    def group_label(key)
      return "Due-Out Review" if key.to_s == "review_due_out"

      key.to_s.humanize
    end

    def failure_summary
      return nil unless last_attempt&.failed?

      failed_items = Array(last_attempt.summary.to_h.dig("run_results", "failed_items"))
      first_failure = failed_items.first
      # TODO: expose a structured NightAudit failure summary instead of deriving it from logs/run_results.
      first_failure.is_a?(Hash) ? first_failure["error"].presence || first_failure["reason"].presence : nil
    end

    def history_status_label(night_audit)
      return "Force Closed" if night_audit.force_closed?
      return "Retry Available" if night_audit.failed? || night_audit.blocked?

      night_audit.status.to_s.humanize
    end

    def history_status_class(night_audit)
      return "border-red-300 bg-red-50 text-red-800" if night_audit.force_closed?

      case night_audit.status
      when "completed" then "border-emerald-200 bg-emerald-50 text-emerald-700"
      when "blocked" then "border-amber-200 bg-amber-50 text-amber-700"
      when "failed" then "border-red-200 bg-red-50 text-red-700"
      when "running", "pending" then "border-sky-200 bg-sky-50 text-sky-700"
      else "border-border bg-muted text-foreground"
      end
    end

    def finished_at_label(night_audit)
      return format_datetime(night_audit.completed_at) if night_audit.completed_at.present?
      return "Scheduled" if night_audit.pending?
      return "In progress" if night_audit.running?

      "Not finished"
    end

    def format_datetime(value)
      value&.in_time_zone(hotel.hotel_time_zone)&.strftime("%d %b %Y, %I:%M %p") || "Not available"
    end
    end
  end
end
