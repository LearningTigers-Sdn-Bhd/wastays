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

      reconciliation = current_reconciliation
      return success(reconciliation, already_repaired: true) if reconciliation.valid?

      repair = Folios::Charges::RepairNightlyChargeReconciliation.call(
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
      return failure(repair.error) unless repair.success?

      evaluation = evaluate_and_persist!
      record_resolution_log!(repair)
      success(
        repair.reconciliation,
        evaluation: evaluation,
        reversed_transactions: repair.reversed_transactions,
        posted_transactions: repair.posted_transactions
      )
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate_context
      return "You do not have permission to resolve Night Audit blockers." unless allowed_actor?
      return "Booking does not belong to this hotel." unless @booking.hotel_id == @hotel.id
      return "Night audit is not blocked." unless @night_audit.blocked?
      return "Hotel has no current accounting business date." unless current_business_date
      return "Night audit is not for the current accounting business date." unless current_business_date.business_date == @business_date
      return "Business date must be audit blocked before resolving blockers." unless current_business_date.audit_blocked?
      return nil if blocker_booking_ids.include?(@booking.id)
      return nil if current_reconciliation.valid?

      "Booking is not in the missing nightly charges blocker list."
    end

    def allowed_actor?
      return true if @actor&.respond_to?(:superadmin?) && @actor.superadmin?
      return false unless @actor&.respond_to?(:has_permission?)

      @actor.has_permission?(PERMISSION, hotel: @hotel)
    end

    def current_business_date
      @current_business_date ||= @hotel.current_business_date_record
    end

    def blocker_booking_ids
      @blocker_booking_ids ||= begin
        stored_ids = blocker_ids(@night_audit.blocked_details)
        snapshot_ids = blocker_ids(current_business_date.blockers_snapshot)
        fresh_ids = blocker_ids(fresh_evaluation[:blocked_details])
        (stored_ids + snapshot_ids + fresh_ids).uniq
      end
    end

    def blocker_ids(details)
      Array(details.to_h[BLOCKER_TYPE]).filter_map { |item| item["booking_id"] || item[:booking_id] }.map(&:to_i)
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

      @night_audit.update!(
        blocked_details: evaluation[:blocked_details],
        exceptions: evaluation[:exceptions],
        summary: @night_audit.summary.to_h.merge(evaluation[:summary])
      )
      current_business_date.update!(blockers_snapshot: evaluation[:blocked_details])
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
