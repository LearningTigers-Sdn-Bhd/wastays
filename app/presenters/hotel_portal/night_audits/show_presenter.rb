# frozen_string_literal: true

module HotelPortal
  module NightAudits
    class ShowPresenter
    Detail = Struct.new(:label, :value, :tone, :wide?, keyword_init: true)
    Counter = Struct.new(:label, :value, :tone, :detail, :icon, keyword_init: true)
    ResultRow = Struct.new(:result, :reference, :details, :amount, :tone, keyword_init: true)
    IssueRow = Struct.new(:type, :guest, :reference, :details, :tone, keyword_init: true)
    AdjustmentRow = Struct.new(:time, :guest, :reference, :category, :user, :amount, :reason, keyword_init: true)
    HistoricalRepairRow = Struct.new(:booking_id, :guest, :reference, :issue_count, :issue_labels, :line_details, :expected_total, keyword_init: true)

    PAYMENT_STATUS_ORDER = %w[partial pending captured failed refunded voided].freeze
    RUN_RESULT_DEFINITIONS = [
      [ "Status Changes", "status_changes", "info" ],
      [ "Charges Posted", "charges_posted", "success" ],
      [ "Skipped Items", "skipped_items", "warning" ],
      [ "Failed Items", "failed_items", "danger" ]
    ].freeze
    BLOCKER_LABELS = { "missing_folio" => "Accounting blocker" }.freeze
    WARNING_LABELS = { "review_due_out" => "Due-out review carried forward" }.freeze

    attr_reader :night_audit, :adjustments, :completed_nightly_review, :current_user, :view

    def initialize(night_audit:, adjustments:, view_context:, completed_nightly_review: [], current_user: nil)
      @night_audit = night_audit
      @adjustments = adjustments
      @completed_nightly_review = completed_nightly_review
      @current_user = current_user
      @view = view_context
    end

    def title
      "Night Audit / #{format_date(night_audit.business_date)}"
    end

    def subtitle
      [
        status_label,
        night_audit.trigger_mode.to_s.humanize,
        night_audit.performed_by_user&.name || "System",
        finished_at_summary
      ].join(" · ")
    end

    def status_label
      return "Force Closed" if night_audit.force_closed?

      night_audit.status.to_s.humanize
    end

    def status_tone
      return "danger" if night_audit.force_closed?

      case night_audit.status
      when "completed" then "success"
      when "blocked" then "warning"
      when "failed" then "danger"
      when "running" then "info"
      else "neutral"
      end
    end

    def result_banner
      case
      when night_audit.force_closed?
        banner("danger", "triangle-alert", "Date force closed",
          "Business date #{format_date(night_audit.business_date)} was closed by override. #{evidence_summary}")
      when night_audit.completed?
        banner("success", "circle-check", "Date closed",
          "Business date #{format_date(night_audit.business_date)} was closed successfully. #{evidence_summary}")
      when night_audit.blocked?
        banner("danger", "triangle-alert", "Cannot close this date",
          "Resolve all hard blockers before the business date can close. #{evidence_summary}")
      when night_audit.failed?
        banner("danger", "circle-x", "Night Audit failed",
          "The run failed before the business date could close. Review failed items and blockers before retrying.")
      when night_audit.running?
        banner("info", "loader-circle", "Night Audit in progress",
          "The run is evaluating posting and accounting integrity. This page refreshes automatically.")
      else
        banner("neutral", "clock-3", "Audit pending",
          "This Night Audit record is waiting to run. No close decision has been recorded.")
      end
    end

    def audit_details
      details = [
        Detail.new(label: "Business Date", value: format_date(night_audit.business_date)),
        Detail.new(label: "Started At", value: format_datetime(night_audit.started_at)),
        Detail.new(label: "Completed At", value: format_datetime(night_audit.completed_at)),
        Detail.new(label: "Trigger", value: night_audit.trigger_mode.to_s.humanize),
        Detail.new(label: "Performed By", value: night_audit.performed_by_user&.name || "System"),
        Detail.new(label: "Status", value: status_label, tone: status_tone),
        Detail.new(label: "Duration", value: duration_label),
        Detail.new(label: "Audit Packet", value: audit_packet_visible? ? "Available" : "Not available")
      ]
      details << Detail.new(label: "Notes", value: night_audit.notes, wide?: true) if night_audit.notes.present?
      details
    end

    def audit_snapshot
      [
        Counter.new(label: "Arrivals", value: summary_value("arrivals_count"), tone: "neutral", icon: "log-in"),
        Counter.new(label: "Due Outs", value: summary_value("due_out_count"), tone: "neutral", icon: "log-out"),
        Counter.new(label: "Checked Out", value: summary_value("checked_out_count"), tone: "neutral", icon: "circle-check"),
        Counter.new(label: "In-House", value: summary_value("in_house_count"), tone: "neutral", icon: "bed-double"),
        Counter.new(label: "Blockers", value: blocker_rows.count, tone: blocker_rows.any? ? "danger" : "neutral", icon: "triangle-alert"),
        Counter.new(label: "Warnings", value: warning_rows.count, tone: warning_rows.any? ? "warning" : "neutral", icon: "circle-alert")
      ]
    end

    def payment_status_counts
      counts = night_audit.summary.to_h.fetch("payment_status_counts", {}).to_h.stringify_keys
      ordered_keys = PAYMENT_STATUS_ORDER + (counts.keys - PAYMENT_STATUS_ORDER).sort

      ordered_keys.map do |status|
        value = counts.fetch(status, 0)
        Counter.new(label: status.humanize, value: value, tone: payment_tone(status, value))
      end
    end

    def financial_rows
      return [] unless financial_summary

      [
        Detail.new(label: "Room Revenue", value: money(financial_summary.room_revenue)),
        Detail.new(label: "Payments Received", value: money(financial_summary.payments_total), tone: "success"),
        Detail.new(label: "Tax Revenue", value: money(financial_summary.tax_revenue)),
        Detail.new(label: "Refunds Issued", value: money(financial_summary.refunds_total), tone: "danger"),
        Detail.new(label: "No-Show Charges", value: money(financial_summary.no_show_charges)),
        Detail.new(label: "Manual Adjustments", value: money(financial_summary.adjustments_total), tone: "warning")
      ]
    end

    def net_revenue
      return money(0) unless financial_summary

      money(financial_summary.room_revenue + financial_summary.tax_revenue + financial_summary.no_show_charges - financial_summary.refunds_total)
    end

    def run_result_counters
      RUN_RESULT_DEFINITIONS.map do |label, key, tone|
        detail = key == "charges_posted" ? "#{money(run_results.dig(key, 'total').to_d)} posted by this run" : nil
        Counter.new(label: label, value: run_results.dig(key, "count") || 0, tone: tone, detail: detail)
      end
    end

    def run_result_rows
      run_results.flat_map do |key, result|
        Array(result["items"]).map do |item|
          ResultRow.new(
            result: key.humanize,
            reference: item["confirmation_token"].presence || item["booking_id"].presence || item["folio_transaction_id"].presence || "Audit",
            details: result_details(item),
            amount: item["amount"].present? ? money(item["amount"]) : "—",
            tone: result_tone(key)
          )
        end
      end
    end

    def blocker_rows
      issue_rows(night_audit.blocked_details, BLOCKER_LABELS, "danger")
    end

    def warning_rows
      issue_rows(night_audit.exceptions, WARNING_LABELS, "warning")
    end

    def manual_adjustment_rows
      adjustments.map do |adjustment|
        booking = adjustment.booking_folio.booking
        AdjustmentRow.new(
          time: adjustment.created_at.strftime("%H:%M"),
          guest: booking.guest_name,
          reference: booking.confirmation_token,
          category: adjustment.category.humanize,
          user: adjustment.user&.name || "System",
          amount: money(adjustment.amount),
          reason: adjustment.metadata["reason"].presence || "—"
        )
      end
    end

    def historical_repair_rows
      @historical_repair_rows ||= completed_nightly_review.map do |entry|
        issue_labels = entry.issues.flat_map { |issue| issue["issue_types"] }.uniq.map(&:humanize)
        line_details = entry.issues.map do |issue|
          [ issue["description"], issue["expected_folio_reference"], money(issue["expected_amount"]) ].compact.join(" · ")
        end

        HistoricalRepairRow.new(
          booking_id: entry.booking.id,
          guest: entry.booking.guest_name,
          reference: entry.booking.confirmation_token,
          issue_count: entry.issues.count,
          issue_labels: issue_labels,
          line_details: line_details,
          expected_total: money(entry.expected_total)
        )
      end
    end

    def completed_reconciliation_visible?
      night_audit.completed?
    end

    def can_repair_completed_audit?
      return false unless current_user&.respond_to?(:has_permission?)

      current_user.has_permission?("manage_night_audit", hotel: night_audit.hotel) &&
        current_user.has_permission?(FinancialControls::PostingGuard::OVERRIDE_PERMISSION, hotel: night_audit.hotel)
    end

    def empty_state(key)
      {
        financial: "No financial summary was recorded for this Night Audit.",
        run_results: "No item-level run results were recorded.",
        blockers: "No audit blockers were recorded.",
        warnings: "No warnings or review items were recorded.",
        adjustments: "No manual adjustments or voids were recorded for this business date."
      }.fetch(key)
    end

    def auto_refresh?
      night_audit.running?
    end

    def audit_packet_visible?
      night_audit.completed?
    end

    def resolve_blockers_visible?
      night_audit.blocked?
    end

    def manual_adjustments_open?
      manual_adjustment_rows.any?
    end

    private

    def banner(tone, icon, title, message)
      { tone: tone, icon: icon, title: title, message: message }
    end

    def evidence_summary
      "#{warning_rows.count} #{'review item'.pluralize(warning_rows.count)} carried forward. #{blocker_rows.count} #{'hard blocker'.pluralize(blocker_rows.count)} recorded."
    end

    def finished_at_summary
      if night_audit.completed_at.present?
        "Closed #{format_datetime(night_audit.completed_at)}"
      elsif night_audit.running?
        "Started #{format_datetime(night_audit.started_at)}"
      else
        "Not completed"
      end
    end

    def duration_label
      return "In progress" if night_audit.running?
      return "Not available" unless night_audit.started_at && night_audit.completed_at

      seconds = (night_audit.completed_at - night_audit.started_at).round
      return "< 1 minute" if seconds < 60

      view.distance_of_time_in_words(night_audit.started_at, night_audit.completed_at)
    end

    def format_date(date)
      date&.strftime("%d %b %Y") || "Not available"
    end

    def format_datetime(time)
      time&.strftime("%d %b %Y, %I:%M %p") || "Not available"
    end

    def money(value)
      view.number_to_currency(value.to_d)
    end

    def financial_summary
      night_audit.financial_summary
    end

    def summary_value(key)
      night_audit.summary.to_h[key] || 0
    end

    def run_results
      night_audit.summary.to_h.fetch("run_results", {}).to_h
    end

    def result_details(item)
      item["reason"].presence ||
        [ item["from"], item["to"] ].compact.join(" → ").presence ||
        [ item["category"]&.humanize, item["posting_date"] ].compact.join(" · ").presence ||
        "No additional details"
    end

    def result_tone(key)
      RUN_RESULT_DEFINITIONS.find { |_, result_key, _| result_key == key }&.last || "neutral"
    end

    def payment_tone(status, value)
      return "neutral" unless value.to_i.positive?

      case status
      when "captured" then "success"
      when "failed" then "danger"
      when "partial", "pending" then "warning"
      else "neutral"
      end
    end

    def issue_rows(source, labels, tone)
      source.to_h.flat_map do |type, rows|
        Array(rows).map do |row|
          IssueRow.new(
            type: labels.fetch(type.to_s, type.to_s.humanize),
            guest: row["guest_name"].presence || "N/A",
            reference: row["confirmation_token"].presence || "N/A",
            details: row["reason"].presence || row["details"].presence || row["message"].presence || "General exception",
            tone: tone
          )
        end
      end
    end
    end
  end
end
