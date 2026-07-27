# frozen_string_literal: true

module NightAudits
  class RepairCompletedNightlyCharges
    MANAGE_PERMISSION = "manage_night_audit"
    OVERRIDE_PERMISSION = FinancialControls::PostingGuard::OVERRIDE_PERMISSION
    POSTING_SOURCE = "historical_nightly_charge_repair"
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
      @reason = reason.to_s.strip
    end

    def call
      validation_error = validate_context
      return failure(validation_error) if validation_error.present?

      reconciliation = current_reconciliation
      return success(reconciliation, already_repaired: true) if reconciliation.valid?

      repair = nil
      ActiveRecord::Base.transaction do
        repair = Folios::Charges::RepairNightlyChargeReconciliation.call(
          booking: @booking,
          reconciliation: reconciliation,
          actor: @actor,
          reason: @reason,
          night_audit: @night_audit,
          posting_options: {
            posting_source: POSTING_SOURCE,
            override_night_audit: true,
            override_closed_folio: true,
            correction_reason: @reason,
            correction_note: @reason,
            permission_context: @actor,
            system_posting: true
          }
        )
        raise repair.error unless repair.success?

        NightAudits::RecalculateFinancialSummary.new(
          hotel: @hotel,
          business_date: @business_date,
          user: @actor,
          reason: @reason
        ).call
        Financials::CreateJournalBatch.call(hotel: @hotel, business_date: @business_date)
        record_repair_log!(repair)
      end

      success(
        repair.reconciliation,
        reversed_transactions: repair.reversed_transactions,
        posted_transactions: repair.posted_transactions
      )
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate_context
      return "You do not have permission to manage Night Audit." unless allowed_actor?(MANAGE_PERMISSION)
      return "You do not have permission to post corrections to a closed business date." unless allowed_actor?(OVERRIDE_PERMISSION)
      return "A correction reason is required." if @reason.blank?
      return "Booking does not belong to this hotel." unless @booking.hotel_id == @hotel.id
      return "Night audit must be completed before historical charges can be repaired." unless @night_audit.completed?
      return "Booking did not occupy this business date." unless booking_stay_dates.include?(@business_date)

      nil
    end

    def allowed_actor?(permission)
      return true if @actor&.respond_to?(:superadmin?) && @actor.superadmin?
      return false unless @actor&.respond_to?(:has_permission?)

      @actor.has_permission?(permission, hotel: @hotel)
    end

    def booking_stay_dates
      @booking_stay_dates ||= Bookings::ScheduledStay.stay_dates(
        hotel: @hotel,
        check_in: @booking.check_in,
        check_out: @booking.check_out
      )
    end

    def current_reconciliation
      @current_reconciliation ||= Folios::Charges::NightlyChargeReconciliation.call(
        booking: @booking,
        business_date: @business_date,
        allow_closed_folio: true
      )
    end

    def record_repair_log!(repair)
      NightAudits::RecordLog.call!(
        night_audit: @night_audit,
        user: @actor,
        action_type: "completed_audit_repair",
        message: "Repaired completed-audit nightly charges for booking #{@booking.confirmation_token}",
        metadata: {
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          business_date: @business_date.iso8601,
          operation_key: repair.operation_key,
          reversed_transaction_ids: repair.reversed_transactions.map(&:id),
          posted_transaction_ids: repair.posted_transactions.map(&:id),
          reason: @reason
        }
      )
    end

    def success(reconciliation, already_repaired: false, reversed_transactions: [], posted_transactions: [])
      message = already_repaired ? "Nightly charges are already reconciled." : "Historical nightly charges repaired and accounting summaries refreshed."
      Result.success(
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
