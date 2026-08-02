# frozen_string_literal: true

module NightAudits
  module Execution
    class PersistFailure
      def self.call(**attributes)
        new(**attributes).call
      end

      def initialize(hotel:, business_date:, business_date_record:, night_audit:, actor:, trigger_mode:, notes:, error_message:)
        @hotel = hotel
        @business_date = business_date.to_date
        @business_date_record = business_date_record
        @night_audit = night_audit
        @actor = actor
        @trigger_mode = trigger_mode
        @notes = notes
        @error_message = error_message
      end

      def call
        block_business_date
        failed_audit = @night_audit.presence || @hotel.night_audits.find_or_initialize_by(business_date: @business_date)
        persist_failed_audit!(failed_audit)
        record_log!(failed_audit)
        failed_audit.update_column(:summary, summary_with_run_results(failed_audit))
        record_failure_events(failed_audit)
        failed_audit
      end

      private

      def block_business_date
        return unless @business_date_record

        @business_date_record.reload
        return unless @business_date_record.audit_running?

        BusinessDates::BlockAudit.call!(
          hotel: @hotel,
          blockers: { "audit_failure" => [ { "message" => @error_message } ] },
          actor: @actor,
          system_context: true
        )
      rescue StandardError => e
        Rails.logger.error("Failed to mark business date blocked after night audit failure: #{e.message}")
      end

      def persist_failed_audit!(failed_audit)
        failed_audit.assign_attributes(
          status: "failed",
          trigger_mode: @trigger_mode,
          performed_by_user: @actor,
          completed_at: Time.current,
          notes: @notes,
          force_closed: false
        )
        failed_audit.started_at ||= Time.current
        failed_audit.summary ||= {}
        failed_audit.blocked_details ||= {}
        failed_audit.exceptions ||= {}
        failed_audit.save!(validate: false)
      end

      def record_log!(failed_audit)
        NightAudits::RecordLog.call!(
          night_audit: failed_audit,
          user: @actor,
          action_type: "failed",
          message: "Night audit failed: #{@error_message}",
          metadata: { error: @error_message }
        )
      end

      def summary_with_run_results(failed_audit)
        failed_audit.summary.to_h.merge(
          "run_results" => NightAudits::BuildRunResults.call(night_audit: failed_audit)
        )
      end

      def record_failure_events(failed_audit)
        current = HotelBusinessDate.find_by(hotel: @hotel, business_date: @business_date)
        safe_record_event(failed_audit, current, "night_audit_failed", "Night audit failed", error: @error_message)
        return unless current&.audit_blocked?

        safe_record_event(failed_audit, current, "business_date_audit_blocked", "Business date moved to audit_blocked", error: @error_message)
      end

      def safe_record_event(failed_audit, business_date, event_type, reason, metadata)
        FinancialControls::AuditEventRecorder.call!(
          hotel: @hotel,
          business_date: business_date&.business_date || @business_date,
          event_type: event_type,
          source: "night_audit",
          actor: @actor,
          night_audit: failed_audit,
          hotel_business_date: business_date,
          reason: reason,
          metadata: metadata.merge(
            night_audit_status: failed_audit.status,
            trigger_mode: @trigger_mode
          )
        )
      rescue StandardError => e
        Rails.logger.error("Failed to record financial audit event #{event_type} for night audit #{failed_audit.id}: #{e.message}")
      end
    end
  end
end
