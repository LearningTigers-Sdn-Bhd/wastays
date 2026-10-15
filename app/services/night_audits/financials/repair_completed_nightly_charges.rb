# frozen_string_literal: true

module NightAudits
  module Financials
  class RepairCompletedNightlyCharges
    MANAGE_PERMISSION = "manage_night_audit"
    OVERRIDE_PERMISSION = FinancialControls::PostingGuard::OVERRIDE_PERMISSION
    POSTING_SOURCE = "historical_nightly_charge_repair"
    Result = ApplicationResult.define(:already_repaired?, :reconciliation, :reversed_transactions, :posted_transactions, :message)

    def self.call(night_audit:, booking:, actor:, reason:)
      new(night_audit: night_audit, booking: booking, actor: actor, reason: reason).call
    end

    def initialize(night_audit:, booking:, actor:, reason:, business_date: nil)
      @night_audit = night_audit
      @booking = booking
      @actor = actor
      @hotel = night_audit&.hotel || booking.hotel
      @business_date = (business_date || night_audit.business_date).to_date
      @reason = reason.to_s.strip
    end

    def call
      validation_error = validate_context
      return failure(validation_error) if validation_error.present?

      perform_repair
    rescue StandardError => e
      failure(e.message)
    end

    # Stay edits may add missing charges, but must not alter historical postings.
    def call_for_stay_update
      @stay_update = true
      return failure("You do not have permission to update this booking.") unless allowed_actor?("manage_bookings")
      return failure("Only in-house stays can post missing historical charges automatically.") unless @booking.status.in?(Booking::IN_HOUSE_STATUSES)

      validation_error = validate_booking_context
      return failure(validation_error) if validation_error.present?
      return failure("Existing closed-night charges require an accounting correction.") if current_reconciliation.entries.any? { |entry| entry[:issues].any? && entry[:transactions].any? }

      perform_repair
    rescue StandardError => e
      failure(e.message)
    end

    def call_for_stay_correction(removed_transactions: [])
      @stay_update = true
      @removed_transactions = removed_transactions
      return failure("You do not have permission to update this booking.") unless allowed_actor?("manage_bookings")
      return failure("Only in-house stays can correct historical charges here.") unless @booking.status.in?(Booking::IN_HOUSE_STATUSES)
      return failure("Closed folios cannot be corrected through stay dates.") if @removed_transactions.any? { |transaction| !transaction.booking_folio.open? }

      validation_error = validate_context
      return failure(validation_error) if validation_error.present?

      perform_repair
    rescue StandardError => e
      failure(e.message)
    end

    # Explicitly scoped by the reviewed completed-booking correction. Ordinary
    # stay edits retain their in-house-only guards and full reconciliation.
    def call_for_room_correction(charge_keys:, removed_transactions: [])
      return failure("Only checked-out bookings can use room-charge correction.") unless @booking.status == "completed"
      %w[manage_bookings override_booking_rate post_folio_corrections manage_night_audit override_financial_date_lock].each do |permission|
        return failure("You do not have permission to correct room charges (#{permission}).") unless allowed_actor?(permission)
      end
      return failure("A correction reason is required.") if @reason.blank?
      return failure("Booking does not belong to this hotel.") unless @booking.hotel_id == @hotel.id
      return failure("Night Audit does not match the correction date.") if @night_audit && @night_audit.business_date != @business_date
      allowed_keys = Bookings::BuildRoomChargeCorrectionSnapshot.charge_keys_for(booking: @booking)
      unless charge_keys.present? && (charge_keys - allowed_keys).empty? && booking_stay_dates.include?(@business_date)
        return failure("Only this booking's nightly room and associated tax charges can be corrected here.")
      end
      removed_transactions.each do |transaction|
        key = transaction.metadata["nightly_charge_key"].presence || transaction.metadata["reconciles_nightly_charge_key"].presence ||
          (transaction.catch_up_key.presence || transaction.metadata["catch_up_key"].presence).to_s.delete_prefix("catch_up:")
        unless transaction.source_booking_id == @booking.id && transaction.posting_date == @business_date && charge_keys.include?(key)
          return failure("Removed charges must belong to the reviewed room correction.")
        end
      end
      record = @hotel.hotel_business_dates.find_by(business_date: @business_date)
      unless (record&.open? && record.id == @hotel.current_business_date_record&.id) || (record&.closed_like? && @night_audit&.completed?)
        return failure("Resolve Night Audit for #{@business_date} before correcting room charges.")
      end
      reconciliation = Folios::Charges::NightlyChargeReconciliation.call(booking: @booking, business_date: @business_date, charge_keys: charge_keys)
      return failure("Affected folios must be open for correction.") if (reconciliation.entries.map { |entry| entry[:route].folio } + removed_transactions.map(&:booking_folio)).compact.any? { |folio| !folio.open? }

      @charge_keys = charge_keys
      @removed_transactions = removed_transactions
      @reconciliation = reconciliation
      @room_correction = true
      perform_repair
    rescue StandardError => e
      failure(e.message)
    end

    private

    def perform_repair
      reconciliation = current_reconciliation
      return success(reconciliation, already_repaired: true) if reconciliation.valid? && @removed_transactions.to_a.empty?

      repair = nil
      ActiveRecord::Base.transaction do
        repair = Folios::Charges::RepairNightlyChargeReconciliation.call(
          booking: @booking,
          reconciliation: reconciliation,
          actor: @actor,
          reason: @reason,
          night_audit: @night_audit,
          removed_transactions: @removed_transactions.to_a,
          business_date: @business_date,
          charge_keys: @charge_keys,
          posting_options: {
            posting_source: POSTING_SOURCE,
            override_night_audit: true,
            override_closed_folio: !@stay_update && !@room_correction,
            correction_reason: @reason,
            correction_note: @reason,
            permission_context: @actor,
            system_posting: true
          }
        )
        raise repair.error unless repair.success?
        raise "Historical nightly charges did not reconcile." unless repair.reconciliation.valid?

        NightAudits::RecalculateFinancialSummary.new(
          hotel: @hotel,
          business_date: @business_date,
          user: @actor,
          reason: @reason
        ).call
        ::Financials::CreateJournalBatch.call(hotel: @hotel, business_date: @business_date)
        record_repair_log!(repair) if @night_audit
      end

      success(
        repair.reconciliation,
        reversed_transactions: repair.reversed_transactions,
        posted_transactions: repair.posted_transactions
      )
    rescue StandardError => e
      failure(e.message)
    end

    def validate_context
      return "You do not have permission to manage Night Audit." unless allowed_actor?(MANAGE_PERMISSION)
      return "You do not have permission to post corrections to a closed business date." unless allowed_actor?(OVERRIDE_PERMISSION)
      validate_booking_context
    end

    def validate_booking_context
      return "A correction reason is required." if @reason.blank?
      return "Booking does not belong to this hotel." unless @booking.hotel_id == @hotel.id
      return "Night audit must be completed before historical charges can be repaired." unless @night_audit.completed?
      return "Booking did not occupy this business date." unless booking_stay_dates.include?(@business_date) || @removed_transactions.to_a.any?

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
      return @reconciliation if @reconciliation

      @current_reconciliation ||= Folios::Charges::NightlyChargeReconciliation.call(
        booking: @booking,
        business_date: @business_date,
        allow_closed_folio: !@stay_update
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
end
