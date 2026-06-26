# frozen_string_literal: true

require "ostruct"
require "securerandom"

module NightAudits
  class ResolveMissingNightlyCharges
    BLOCKER_TYPE = "missing_nightly_charges"
    PERMISSION = "manage_night_audit"
    POSTING_SOURCE = "audit_blocker_resolution"

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
      @operation_key = SecureRandom.uuid
      @reversed_transactions = []
      @posted_transactions = []
    end

    def call
      validation_error = validate_context
      return failure(validation_error) if validation_error.present?

      reconciliation = current_reconciliation
      return success(reconciliation, already_repaired: true) if reconciliation.valid?

      @booking.with_lock do
        ActiveRecord::Base.transaction do
          reconciliation.entries.each { |entry| repair_entry!(entry) }
          record_operation_log!
        end
      end

      refresh_forecasts!
      evaluation = evaluate_and_persist!
      record_resolution_log!

      success(
        Folios::NightlyChargeReconciliation.call(booking: @booking.reload, business_date: @business_date),
        evaluation: evaluation
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
      @current_reconciliation ||= Folios::NightlyChargeReconciliation.call(
        booking: @booking,
        business_date: @business_date
      )
    end

    def repair_entry!(entry)
      return if entry[:issues].empty?
      raise entry[:route].error unless entry[:route].success?

      canonical = entry[:valid_transactions].min_by(&:id)
      (entry[:transactions] - [ canonical ]).each { |transaction| reverse_transaction!(transaction, entry) }
      post_expected_line!(entry, moved_from: entry[:transactions].min_by(&:id)) if canonical.blank?
    end

    def reverse_transaction!(transaction, entry)
      result = Folios::InsertTransaction.new(
        booking_folio: transaction.booking_folio,
        amount: -transaction.amount,
        transaction_type: "adjustment",
        category: "correction",
        user: @actor,
        description: "Night Audit repair reversal: #{transaction.description}",
        posting_date: @business_date,
        options: blocker_posting_options.merge(
          reversal_of_transaction: transaction,
          metadata: repair_metadata(entry).merge(
            repair_action: "reverse",
            reversed_transaction_id: transaction.id
          )
        )
      ).call
      raise "Failed to reverse nightly charge ##{transaction.id}: #{result.error}" unless result.success?

      transaction.update!(voided_by_transaction: result.transaction)
      @reversed_transactions << result.transaction
    end

    def post_expected_line!(entry, moved_from:)
      line = entry[:line]
      metadata = expected_metadata(entry)
      if nightly_key_occupied_on_target?(entry)
        metadata[:reconciles_nightly_charge_key] = entry[:nightly_charge_key]
      else
        metadata[:nightly_charge_key] = entry[:nightly_charge_key]
      end

      result = Folios::InsertTransaction.new(
        booking_folio: entry[:route].folio,
        amount: line[:amount],
        transaction_type: "charge",
        category: line[:category],
        user: @actor,
        description: line[:description],
        posting_date: @business_date,
        options: blocker_posting_options.merge(
          transaction_code: line[:transaction_code],
          moved_from_transaction: moved_from,
          metadata: metadata
        )
      ).call
      raise "Failed to repost nightly charge #{entry[:nightly_charge_key]}: #{result.error}" unless result.success?

      @posted_transactions << result.transaction
    end

    def blocker_posting_options
      {
        posting_source: POSTING_SOURCE,
        system_posting: true,
        correction_reason: @reason,
        night_audit: @night_audit,
        blocker_resolution: blocker_resolution_metadata
      }
    end

    def blocker_resolution_metadata
      {
        night_audit_id: @night_audit.id,
        blocker_type: BLOCKER_TYPE,
        booking_id: @booking.id,
        operation_key: @operation_key
      }
    end

    def expected_metadata(entry)
      line = entry[:line]
      {
        posting_source: POSTING_SOURCE,
        night_audit_id: @night_audit.id,
        stay_date: @business_date.iso8601,
        booking_id: @booking.id,
        charge_kind: line[:charge_kind],
        forecast_identity: line[:identity].to_s,
        tax_line: line[:tax_line],
        route_source: entry[:route].route_source,
        route_metadata: entry[:route].route_metadata,
        blocker_resolution: blocker_resolution_metadata,
        repair_action: "repost",
        operation_key: @operation_key,
        repaired_by_user_id: @actor&.id
      }.compact
    end

    def repair_metadata(entry)
      {
        posting_source: POSTING_SOURCE,
        night_audit_id: @night_audit.id,
        stay_date: @business_date.iso8601,
        booking_id: @booking.id,
        charge_kind: entry[:line][:charge_kind],
        forecast_identity: entry[:line][:identity].to_s,
        blocker_resolution: blocker_resolution_metadata,
        operation_key: @operation_key,
        repaired_by_user_id: @actor&.id
      }
    end

    def nightly_key_occupied_on_target?(entry)
      entry[:route].folio.folio_transactions.where(
        "metadata->>'nightly_charge_key' = ?",
        entry[:nightly_charge_key]
      ).exists?
    end

    def refresh_forecasts!
      Folios::SyncForecastedCharges.call(booking_folio: @booking.booking_folio) if @booking.booking_folio.present?
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

    def record_operation_log!
      return if @reversed_transactions.empty? && @posted_transactions.empty?

      FolioOperationLog.create!(
        hotel: @hotel,
        booking: @booking,
        actor: @actor,
        operation_type: "correction",
        source_folio: @reversed_transactions.first&.booking_folio,
        target_folio: @posted_transactions.first&.booking_folio,
        source_transaction: @reversed_transactions.first&.reversal_of_transaction,
        target_transaction: @posted_transactions.first,
        amount: @posted_transactions.sum { |transaction| transaction.amount.to_d },
        currency: @booking.currency,
        operation_key: @operation_key,
        reason: @reason,
        metadata: {
          correction_type: "nightly_charge_repair",
          night_audit_id: @night_audit.id,
          business_date: @business_date.iso8601,
          reversed_transaction_ids: @reversed_transactions.map(&:id),
          posted_transaction_ids: @posted_transactions.map(&:id)
        }
      )
    end

    def record_resolution_log!
      NightAudits::RecordLog.call!(
        night_audit: @night_audit,
        user: @actor,
        action_type: "blocker_resolved",
        message: "Repaired nightly charges for booking #{@booking.confirmation_token}",
        metadata: {
          blocker_type: BLOCKER_TYPE,
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          operation_key: @operation_key,
          reversed_transaction_ids: @reversed_transactions.map(&:id),
          posted_transaction_ids: @posted_transactions.map(&:id),
          reason: @reason
        }
      )
    end

    def success(reconciliation, evaluation: nil, already_repaired: false)
      remaining = evaluation ? Array(evaluation[:blocked_details][BLOCKER_TYPE]).any? { |item| item["booking_id"].to_i == @booking.id } : !reconciliation.valid?
      OpenStruct.new(
        success?: !remaining,
        already_repaired?: already_repaired,
        reconciliation: reconciliation,
        reversed_transactions: @reversed_transactions,
        posted_transactions: @posted_transactions,
        message: remaining ? "Nightly charges still require attention." : (already_repaired ? "Nightly charges are already reconciled." : "Nightly charges repaired. Retry Night Audit.")
      )
    end

    def failure(error)
      OpenStruct.new(
        success?: false,
        already_repaired?: false,
        reconciliation: nil,
        reversed_transactions: [],
        posted_transactions: [],
        error: error,
        message: error
      )
    end
  end
end
