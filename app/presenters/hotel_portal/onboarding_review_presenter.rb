# frozen_string_literal: true

module HotelPortal
  class OnboardingReviewPresenter
    Metric = Data.define(:label, :value, :detail, :detail_variant)
    Row = Data.define(:entry, :title, :summary, :status_label, :status_variant, :action_label)
    Group = Data.define(:key, :label, :rows)

    INVITATION_DELIVERY_TYPES = %w[staff_invitation corporate_invitation].freeze

    def initialize(hotel:, navigation:, readiness:, submission:, snapshot:)
      @hotel = hotel
      @navigation = navigation
      @readiness = readiness
      @submission = submission
      @snapshot = snapshot.to_h.deep_stringify_keys
      @snapshot_summary = Onboarding::SnapshotSummaryPresenter.new(snapshot: @snapshot)
      @findings = (readiness.blocking_issues + readiness.warnings).index_by(&:section_key)
    end

    attr_reader :hotel, :navigation, :readiness, :submission, :snapshot

    def title
      {
        ready: "Review & submit",
        blocked: "Review & submit",
        changes_requested: "Changes requested",
        pending: "Setup submitted",
        approved: "Setup approved"
      }.fetch(page_state)
    end

    def description
      {
        ready: "Check the setup below before sending it to WAStays.",
        blocked: "Resolve the items that need attention before sending the setup to WAStays.",
        changes_requested: "Update the requested sections, then send the setup back to WAStays.",
        pending: "WAStays is reviewing the submitted property setup.",
        approved: "This property is live. The approved setup remains available for reference."
      }.fetch(page_state)
    end

    def status_title
      {
        ready: "Ready to submit",
        blocked: "Setup needs attention",
        changes_requested: "WAStays requested changes",
        pending: "Awaiting WAStays review",
        approved: "Property is live"
      }.fetch(page_state)
    end

    def status_tone
      {
        ready: :success,
        blocked: :warning,
        changes_requested: :warning,
        pending: :info,
        approved: :success
      }.fetch(page_state)
    end

    def status_description
      case page_state
      when :ready
        "All required setup is complete. Check the choices below, then send the property to WAStays."
      when :blocked
        count = attention_section_count
        "Resolve #{count} #{'section'.pluralize(count)} before submitting for review."
      when :changes_requested
        submission&.review_explanation.presence || "Review the sections marked Needs attention before submitting again."
      when :pending
        "Submitted by #{submission&.submitted_by&.name || 'a property administrator'}#{event_time(submission&.submitted_at)}. Editing is locked while WAStays reviews this property."
      when :approved
        reviewer = submission&.reviewed_by&.name || "WAStays"
        "Approved by #{reviewer}#{event_time(submission&.reviewed_at)}. This property is live."
      end
    end

    def metrics
      submitted? ? delivery_metrics : setup_metrics
    end

    def groups
      @snapshot_summary.groups.map do |group|
        rows = group.rows.map do |snapshot_row|
          entry = navigation.fetch(snapshot_row.definition.key)
          row_for(entry, snapshot_row)
        end
        Group.new(key: group.key, label: group.label, rows:)
      end
    end

    def submit_label = changes_requested? ? "Submit changes for review" : "Submit for review"

    private

    def page_state
      @page_state ||= if submission&.approved? || hotel.status == "live"
        :approved
      elsif hotel.status == "pending_review"
        :pending
      elsif changes_requested?
        :changes_requested
      elsif readiness.ready
        :ready
      else
        :blocked
      end
    end

    def submitted? = page_state.in?(%i[pending approved])

    def changes_requested?
      submission&.changes_requested? || navigation.fetch("review").record.state == "needs_attention"
    end

    def setup_metrics
      entries = navigation.entries.reject { |entry| entry.definition.key == "review" }
      required = entries.select { |entry| entry.definition.required }
      optional = entries.reject { |entry| entry.definition.required }
      required_complete = required.count { |entry| entry.record.state == "complete" }
      optional_resolved = optional.count { |entry| entry.record.resolved? }
      deferred = optional.count { |entry| entry.record.state == "skipped" }
      invitations = invitation_rows
      sending = invitations.count { |row| row["send_invitation"] == true }
      held = invitations.size - sending

      required_metric = Metric.new(
        label: "Required setup", value: "#{required_complete} of #{required.size}",
        detail: required_complete == required.size ? "Complete" : "#{required.size - required_complete} remaining",
        detail_variant: required_complete == required.size ? :success : :warning
      )
      optional_metric = Metric.new(
        label: "Optional decisions", value: "#{optional_resolved} of #{optional.size}",
        detail: "#{deferred} deferred", detail_variant: optional_resolved == optional.size ? :success : :warning
      )
      attention_metric = Metric.new(
        label: "Needs attention", value: attention_section_count.to_s,
        detail: attention_section_count.zero? ? "No sections" : "#{attention_section_count} #{'section'.pluralize(attention_section_count)}",
        detail_variant: attention_section_count.zero? ? :success : :destructive
      )
      invitation_metric = Metric.new(
        label: "Invitations", value: invitations.size.to_s,
        detail: "#{sending} send · #{held} hold", detail_variant: :neutral
      )

      return [ attention_metric, required_metric, optional_metric, invitation_metric ] if changes_requested?

      [ required_metric, optional_metric, attention_metric, invitation_metric ]
    end

    def delivery_metrics
      deliveries = Array(submission&.deliveries).select { |delivery| delivery.delivery_type.in?(INVITATION_DELIVERY_TYPES) }
      counts = deliveries.group_by(&:status).transform_values(&:size)

      [
        Metric.new(label: "Sent", value: counts.fetch("sent", 0).to_s, detail: "Invitations", detail_variant: :success),
        Metric.new(label: "Held", value: counts.fetch("held", 0).to_s, detail: "Invitations", detail_variant: :neutral),
        Metric.new(label: "Pending", value: (counts.fetch("pending", 0) + counts.fetch("processing", 0)).to_s,
                   detail: "Invitations", detail_variant: :warning),
        Metric.new(label: "Failed", value: counts.fetch("failed", 0).to_s, detail: "Invitations", detail_variant: :destructive)
      ]
    end

    def row_for(entry, snapshot_row)
      finding = @findings[entry.definition.key]
      status_label = snapshot_row.status_label
      status_variant = snapshot_row.status_variant
      if finding&.severity == :blocking
        status_label = Onboarding::SnapshotSummaryPresenter::STATE_LABELS.fetch("needs_attention")
        status_variant = Onboarding::SnapshotSummaryPresenter::STATE_VARIANTS.fetch("needs_attention")
      end

      Row.new(
        entry:,
        title: snapshot_row.title,
        summary: snapshot_row.summary,
        status_label:,
        status_variant:,
        action_label: finding&.severity == :blocking && !submitted? ? "Fix" : "View"
      )
    end

    def invitation_rows = Array(snapshot["staff"]) + Array(commercial["corporate_accounts"])
    def commercial = snapshot.fetch("commercial", {})
    def attention_section_count = @findings.values.count { |finding| finding.severity == :blocking }

    def event_time(value)
      value.present? ? " on #{I18n.l(value, format: :long)}" : ""
    end
  end
end
