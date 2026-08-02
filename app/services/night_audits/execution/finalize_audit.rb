# frozen_string_literal: true

module NightAudits
  module Execution
    class FinalizeAudit
      Result = Data.define(:business_date, :next_business_date)

      def self.call(**attributes)
        new(**attributes).call
      end

      def initialize(hotel:, night_audit:, business_date:, evaluation:, financial_totals:, summary:, actor:, force_roll:, notes:, trigger_mode:, phase:)
        @hotel = hotel
        @night_audit = night_audit
        @business_date = business_date
        @evaluation = evaluation
        @financial_totals = financial_totals
        @summary = summary
        @actor = actor
        @force_roll = force_roll
        @notes = notes
        @trigger_mode = trigger_mode
        @phase = phase.to_sym
      end

      def call
        return finalize_pre_close_block if @phase == :pre_close

        finalize_post_close
      end

      private

      def finalize_pre_close_block
        ActiveRecord::Base.transaction do
          persist_financial_summary
          update_night_audit!(status: "blocked", force_closed: false)
          block_business_date!
        end

        safe_record_event("night_audit_blocked", "Night audit blocked before posting", blockers: blocked_details)
        safe_record_event("business_date_audit_blocked", "Business date moved to audit_blocked", blockers: blocked_details)
        Result.new(business_date: @business_date, next_business_date: nil)
      end

      def finalize_post_close
        next_business_date = nil

        ActiveRecord::Base.transaction do
          persist_financial_summary
          blocked = blocked?
          final_status = blocked && !@force_roll ? "blocked" : "completed"
          update_night_audit!(status: final_status, force_closed: @force_roll && blocked)

          if final_status == "completed"
            block_business_date! if @force_roll && blocked
            close_result = close_business_date!(blocked)
            @business_date = close_result.closed_business_date
            next_business_date = close_result.next_business_date
            ::Financials::CreateJournalBatch.call(hotel: @hotel, business_date: @night_audit.business_date)
            persist_completion_event!(blocked)
          else
            block_business_date!
          end
        end

        unless @night_audit.completed?
          safe_record_event("night_audit_blocked", "Night audit blocked after posting", blockers: blocked_details)
          safe_record_event("business_date_audit_blocked", "Business date moved to audit_blocked", blockers: blocked_details)
        end

        Result.new(business_date: @business_date, next_business_date: next_business_date)
      end

      def update_night_audit!(status:, force_closed:)
        @night_audit.update!(
          status: status,
          completed_at: Time.current,
          summary: @summary,
          blocked_details: blocked_details,
          exceptions: @evaluation[:exceptions],
          force_closed: force_closed
        )
      end

      def persist_financial_summary
        summary = @night_audit.financial_summary || @night_audit.build_financial_summary
        summary.assign_attributes(@financial_totals)
        summary.save!
      end

      def block_business_date!
        BusinessDates::BlockAudit.call!(
          hotel: @hotel,
          blockers: blocked_details,
          actor: @actor,
          system_context: true
        )
      end

      def close_business_date!(blocked)
        BusinessDates::CloseAndOpenNext.call!(
          hotel: @hotel,
          actor: @actor,
          system_context: !@force_roll,
          force: @force_roll && blocked,
          reason: @notes,
          blockers: blocked_details,
          night_audit: @night_audit
        )
      end

      def persist_completion_event!(blocked)
        force_rolled = @force_roll && blocked
        persist_event!(
          force_rolled ? "night_audit_force_rolled" : "night_audit_completed",
          force_rolled ? "Night audit force-rolled with blockers" : "Night audit completed",
          financial_totals: @financial_totals
        )
      end

      def blocked?
        blocked_details.values.flatten.any?
      end

      def blocked_details
        @evaluation[:blocked_details]
      end

      def safe_record_event(event_type, reason, metadata = {})
        persist_event!(event_type, reason, metadata)
      rescue StandardError => e
        Rails.logger.error("Failed to record financial audit event #{event_type} for night audit #{@night_audit.id}: #{e.message}")
      end

      def persist_event!(event_type, reason, metadata = {})
        FinancialControls::AuditEventRecorder.call!(
          hotel: @hotel,
          business_date: @business_date&.business_date || @night_audit.business_date,
          event_type: event_type,
          source: "night_audit",
          actor: @actor,
          night_audit: @night_audit,
          hotel_business_date: @business_date,
          reason: reason,
          metadata: metadata.merge(
            night_audit_status: @night_audit.status,
            trigger_mode: @trigger_mode
          )
        )
      end
    end
  end
end
