# frozen_string_literal: true

module NightAudits
  class ResolveMissingNightlyCharges
    BLOCKER_TYPE = "missing_nightly_charges"
    PERMISSION = "manage_night_audit"
    POSTING_SOURCE = "audit_blocker_resolution"
    Result = ApplicationResult.define(:already_repaired?, :reconciliation, :reversed_transactions, :posted_transactions, :message)

    def self.call(night_audit:, booking:, actor:, reason:)
      new(night_audit: night_audit, booking: booking, actor: actor, reason: reason).call
    end

    def initialize(night_audit:, booking:, actor:, reason:)
      @night_audit = night_audit
      @booking = booking
      @actor = actor
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date.to_date
      @reason = reason.to_s.strip.presence || "Repair nightly charges from Night Audit blocker resolution."
    end

    def call
      validation_error = validate_context
      return failure(validation_error) if validation_error.present?

      ActiveRecord::Base.transaction do
        reconciliation = current_reconciliation
        if reconciliation.valid?
          evaluation = evaluate_and_persist!
          next success(reconciliation, evaluation: evaluation, already_repaired: true)
        end

        repair = repair(reconciliation)
        raise repair.error unless repair.success?

        evaluation = evaluate_and_persist!
        record_resolution_log!(repair)
        success(
          repair.reconciliation,
          evaluation: evaluation,
          reversed_transactions: repair.reversed_transactions,
          posted_transactions: repair.posted_transactions
        )
      end
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate_context
      NightAudits::Resolutions::ValidateContext.call(
        night_audit: @night_audit,
        booking: @booking,
        actor: @actor,
        business_date_record: current_business_date,
        blocker_booking_ids: -> { blocker_booking_ids },
        blocker_name: "missing nightly charges",
        permission: PERMISSION,
        allow_unlisted: -> { current_reconciliation.valid? }
      )
    end

    def current_business_date
      @current_business_date ||= @hotel.current_business_date_record
    end

    def blocker_booking_ids
      @blocker_booking_ids ||= NightAudits::Resolutions::BlockerBookingIds.call(
        night_audit: @night_audit,
        business_date_record: current_business_date,
        blocker_type: BLOCKER_TYPE,
        fresh_blocked_details: fresh_evaluation[:blocked_details]
      )
    end

    def fresh_evaluation
      @fresh_evaluation ||= NightAudits::Evaluate.new(
        hotel: @hotel,
        business_date: @business_date,
        phase: :post_close
      ).call
    end

    def current_reconciliation
      @current_reconciliation ||= Folios::Charges::NightlyChargeReconciliation.call(
        booking: @booking,
        business_date: @business_date
      )
    end

    def repair(reconciliation)
      Folios::Charges::RepairNightlyChargeReconciliation.call(
        booking: @booking,
        reconciliation: reconciliation,
        actor: @actor,
        reason: @reason,
        night_audit: @night_audit,
        posting_options: {
          posting_source: POSTING_SOURCE,
          system_posting: true,
          blocker_resolution: blocker_resolution_metadata
        }
      )
    end

    def blocker_resolution_metadata
      {
        night_audit_id: @night_audit.id,
        blocker_type: BLOCKER_TYPE,
        booking_id: @booking.id
      }
    end

    def evaluate_and_persist!
      evaluation = NightAudits::Evaluate.new(
        hotel: @hotel,
        business_date: @business_date,
        phase: :post_close
      ).call

      NightAudits::Resolutions::RefreshSnapshot.call!(
        night_audit: @night_audit,
        business_date_record: current_business_date,
        evaluation: evaluation
      )
      evaluation
    end

    def record_resolution_log!(repair)
      NightAudits::RecordLog.call!(
        night_audit: @night_audit,
        user: @actor,
        action_type: "blocker_resolved",
        message: "Repaired nightly charges for booking #{@booking.confirmation_token}",
        metadata: {
          blocker_type: BLOCKER_TYPE,
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          operation_key: repair.operation_key,
          reversed_transaction_ids: repair.reversed_transactions.map(&:id),
          posted_transaction_ids: repair.posted_transactions.map(&:id),
          reason: @reason
        }
      )
    end

    def success(reconciliation, evaluation: nil, already_repaired: false, reversed_transactions: [], posted_transactions: [])
      remaining = evaluation ? Array(evaluation[:blocked_details][BLOCKER_TYPE]).any? { |item| item["booking_id"].to_i == @booking.id } : !reconciliation.valid?
      message = if remaining
        "Nightly charges still require attention."
      elsif already_repaired
        "Nightly charges are already reconciled."
      else
        "Nightly charges repaired. Retry Night Audit."
      end

      Result.build(
        "success?": !remaining,
        error: ("Nightly charges still require attention." if remaining),
        "already_repaired?": already_repaired,
        reconciliation: reconciliation,
        reversed_transactions: reversed_transactions,
        posted_transactions: posted_transactions,
        message: message
      )
    end

    def failure(error)
      Result.failure(
        error,
        "already_repaired?": false,
        reconciliation: nil,
        reversed_transactions: [],
        posted_transactions: [],
        message: error
      )
    end
  end
end
