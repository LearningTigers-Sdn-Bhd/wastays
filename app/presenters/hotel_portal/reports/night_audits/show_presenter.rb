# frozen_string_literal: true

module HotelPortal
  module Reports
    module NightAudits
      class ShowPresenter
        DetailRow = Data.define(:label, :value)
        ResultRow = Data.define(:result, :reference, :details, :amount, :variant)
        IssueRow = Data.define(:severity, :type, :reference, :details, :variant)
        AdjustmentRow = Data.define(:time, :guest, :reference, :category, :performed_by, :amount, :reason)

        RESULT_VARIANTS = {
          "status_changes" => :info,
          "charges_posted" => :success,
          "skipped_items" => :warning,
          "failed_items" => :destructive
        }.freeze

        attr_reader :night_audit

        def initialize(night_audit:, currency:, adjustments: [])
          @night_audit = night_audit
          @currency = currency
          @adjustments = adjustments
        end

        def title
          "Night audit report"
        end

        def caption
          "#{format_date(night_audit.business_date)} · #{status_label} · #{performed_by}"
        end

        def status_label
          night_audit.force_closed? ? "Force closed" : night_audit.status.to_s.humanize
        end

        def status_variant
          return :destructive if night_audit.force_closed?

          {
            "completed" => :success,
            "blocked" => :warning,
            "failed" => :destructive,
            "running" => :info
          }.fetch(night_audit.status, :neutral)
        end

        def alert
          case
          when night_audit.force_closed?
            { tone: :destructive, title: "Business date force closed", message: "This report contains unresolved evidence carried through an override close." }
          when night_audit.completed?
            { tone: :success, title: "Business date closed", message: "The Night Audit completed and closed this accounting business date." }
          when night_audit.blocked?
            { tone: :warning, title: "Audit blocked", message: "Hard blockers prevented this accounting business date from closing." }
          when night_audit.failed?
            { tone: :destructive, title: "Audit failed", message: "The run ended before the accounting business date could close." }
          when night_audit.running?
            { tone: :info, title: "Audit in progress", message: "This report reflects the evidence recorded so far." }
          else
            { tone: :default, title: "Audit pending", message: "This run has not recorded a close decision." }
          end
        end

        def audit_metrics
          [
            metric("Arrivals", summary_value("arrivals_count"), "Arrivals in the audit snapshot", "log-in"),
            metric("Due outs", summary_value("due_out_count"), "Departures due for the business date", "log-out"),
            metric("Checked out", summary_value("checked_out_count"), "Departures completed", "circle-check"),
            metric("In-house", summary_value("in_house_count"), "Stays carried into the next date", "bed-double"),
            metric("Blockers", blocker_count, "Hard blockers recorded", "triangle-alert", blocker_count.positive? ? :destructive : :neutral),
            metric("Warnings", warning_count, "Review items carried forward", "circle-alert", warning_count.positive? ? :warning : :neutral)
          ]
        end

        def financial_metrics
          return [] unless financial_summary

          [
            financial_metric("Room revenue", financial_summary.room_revenue, "Accommodation charges"),
            financial_metric("Tax revenue", financial_summary.tax_revenue, "Tax charges recorded"),
            financial_metric("Payments", financial_summary.payments_total, "Payments received", :success),
            financial_metric("Refunds", financial_summary.refunds_total, "Refunds issued", :destructive),
            financial_metric("No-show charges", financial_summary.no_show_charges, "No-show revenue"),
            financial_metric("Net revenue", net_revenue, "Room, tax and no-show revenue less refunds")
          ]
        end

        def detail_rows
          [
            DetailRow.new(label: "Business date", value: format_date(night_audit.business_date)),
            DetailRow.new(label: "Status", value: status_label),
            DetailRow.new(label: "Trigger", value: night_audit.trigger_mode.to_s.humanize),
            DetailRow.new(label: "Performed by", value: performed_by),
            DetailRow.new(label: "Started", value: format_datetime(night_audit.started_at)),
            DetailRow.new(label: "Completed", value: format_datetime(night_audit.completed_at)),
            DetailRow.new(label: "Duration", value: duration),
            DetailRow.new(label: "Notes", value: night_audit.notes.presence || "No notes recorded")
          ]
        end

        def result_rows
          @result_rows ||= run_results.flat_map do |result, payload|
            Array(payload.to_h["items"]).map do |item|
              ResultRow.new(
                result: result.humanize,
                reference: item_reference(item),
                details: item_details(item),
                amount: item["amount"].present? ? money(item["amount"]) : "—",
                variant: RESULT_VARIANTS.fetch(result, :neutral)
              )
            end
          end
        end

        def issue_rows
          blocker_rows + warning_rows
        end

        def blocker_rows
          @blocker_rows ||= issue_source(night_audit.blocked_details, "Blocker", :destructive)
        end

        def warning_rows
          @warning_rows ||= issue_source(night_audit.exceptions, "Warning", :warning)
        end

        def adjustment_rows
          @adjustment_rows ||= adjustments.map do |adjustment|
            booking = adjustment.booking_folio.booking
            AdjustmentRow.new(
              time: format_datetime(adjustment.created_at),
              guest: booking.guest_name,
              reference: booking.confirmation_token,
              category: adjustment.category.humanize,
              performed_by: adjustment.user&.name.presence || "System",
              amount: money(adjustment.amount),
              reason: adjustment.metadata.to_h["reason"].presence || "No reason recorded"
            )
          end
        end

        def export_available?
          night_audit.completed?
        end

        private

        attr_reader :currency, :adjustments

        def financial_summary
          night_audit.financial_summary
        end

        def summary_value(key)
          night_audit.summary.to_h.fetch(key, 0)
        end

        def blocker_count
          issue_count(night_audit.blocked_details)
        end

        def warning_count
          issue_count(night_audit.exceptions)
        end

        def issue_count(source)
          source.to_h.values.sum { |rows| Array(rows).size }
        end

        def metric(label, value, detail, icon, detail_variant = :neutral)
          { label: label, value: value.to_s, detail: detail, icon: icon, detail_variant: detail_variant }
        end

        def financial_metric(label, value, detail, detail_variant = :neutral)
          { label: label, value: money(value), detail: detail, detail_variant: detail_variant }
        end

        def net_revenue
          financial_summary.room_revenue + financial_summary.tax_revenue +
            financial_summary.no_show_charges - financial_summary.refunds_total
        end

        def performed_by
          night_audit.performed_by_user&.name.presence || "System"
        end

        def run_results
          night_audit.summary.to_h.fetch("run_results", {}).to_h
        end

        def item_reference(item)
          item["confirmation_token"].presence || item["booking_id"].presence ||
            item["folio_transaction_id"].presence || "Audit"
        end

        def item_details(item)
          item["reason"].presence ||
            [ item["from"], item["to"] ].compact.join(" → ").presence ||
            [ item["category"]&.humanize, item["posting_date"] ].compact.join(" · ").presence ||
            "No additional details"
        end

        def issue_source(source, severity, variant)
          source.to_h.flat_map do |type, rows|
            Array(rows).map do |row|
              row = row.to_h
              IssueRow.new(
                severity: severity,
                type: type.humanize,
                reference: row["confirmation_token"].presence || row["booking_id"].presence || "Audit",
                details: row["reason"].presence || row["message"].presence || compact_issue_details(row),
                variant: variant
              )
            end
          end
        end

        def compact_issue_details(row)
          row.except("confirmation_token", "booking_id").values.compact.map(&:to_s).reject(&:blank?).join(" · ").presence ||
            "No additional details"
        end

        def duration
          return "In progress" if night_audit.running?
          return "Not available" unless night_audit.started_at && night_audit.completed_at

          seconds = (night_audit.completed_at - night_audit.started_at).round
          return "< 1 minute" if seconds < 60

          ActiveSupport::Duration.build(seconds).inspect
        end

        def money(value)
          CurrencyFormatter.format(value, currency: currency)
        end

        def format_date(value)
          value&.strftime("%d %b %Y") || "Not available"
        end

        def format_datetime(value)
          value&.strftime("%d %b %Y, %H:%M") || "Not available"
        end
      end
    end
  end
end
