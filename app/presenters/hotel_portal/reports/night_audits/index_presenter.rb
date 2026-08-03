# frozen_string_literal: true

module HotelPortal
  module Reports
    module NightAudits
      class IndexPresenter
        Row = Data.define(
          :night_audit,
          :business_date,
          :status_label,
          :status_variant,
          :trigger,
          :performed_by,
          :completed_at,
          :net_revenue
        )

        attr_reader :night_audits

        def initialize(night_audits:, status_counts:, currency:)
          @night_audits = night_audits
          @status_counts = status_counts.stringify_keys
          @currency = currency
        end

        def metrics
          [
            { label: "Report records", value: status_counts.values.sum.to_s, detail: "All visible Night Audit records", icon: "files" },
            { label: "Completed", value: count_for("completed").to_s, detail: "Business dates closed successfully", icon: "circle-check", detail_variant: :success },
            { label: "Blocked", value: count_for("blocked").to_s, detail: "Runs stopped by hard blockers", icon: "triangle-alert", detail_variant: :warning },
            { label: "Failed", value: count_for("failed").to_s, detail: "Runs that ended with an error", icon: "circle-x", detail_variant: :destructive }
          ]
        end

        def rows
          @rows ||= night_audits.map do |audit|
            Row.new(
              night_audit: audit,
              business_date: format_date(audit.business_date),
              status_label: status_label(audit),
              status_variant: status_variant(audit),
              trigger: audit.trigger_mode.to_s.humanize,
              performed_by: audit.performed_by_user&.name.presence || "System",
              completed_at: format_datetime(audit.completed_at),
              net_revenue: money(net_revenue(audit.financial_summary))
            )
          end
        end

        private

        attr_reader :status_counts, :currency

        def count_for(status)
          status_counts.fetch(status, 0)
        end

        def status_label(audit)
          audit.force_closed? ? "Force closed" : audit.status.to_s.humanize
        end

        def status_variant(audit)
          return :destructive if audit.force_closed?

          {
            "completed" => :success,
            "blocked" => :warning,
            "failed" => :destructive,
            "running" => :info
          }.fetch(audit.status, :neutral)
        end

        def net_revenue(summary)
          return 0.to_d unless summary

          summary.room_revenue + summary.tax_revenue + summary.no_show_charges - summary.refunds_total
        end

        def money(value)
          CurrencyFormatter.format(value, currency: currency)
        end

        def format_date(value)
          value&.strftime("%d %b %Y") || "Not available"
        end

        def format_datetime(value)
          value&.strftime("%d %b %Y, %H:%M") || "Not completed"
        end
      end
    end
  end
end
