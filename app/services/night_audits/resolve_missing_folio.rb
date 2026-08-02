# frozen_string_literal: true

require "ostruct"

module NightAudits
  class ResolveMissingFolio
    BLOCKER_TYPE = "missing_folio"
    PERMISSION = "manage_night_audit"

    def self.call(night_audit:, booking:, actor:, reason:)
      new(night_audit: night_audit, booking: booking, actor: actor, reason: reason).call
    end

    def initialize(night_audit:, booking:, actor:, reason:)
      @night_audit = night_audit
      @booking = booking
      @actor = actor
      @hotel = night_audit.hotel
      @reason = reason.to_s.strip.presence || "Recover missing folio from Night Audit blocker resolution."
    end

    def call
      validation_error = validate_context
      return failure(validation_error) if validation_error.present?

      ActiveRecord::Base.transaction do
        recovery = Folios::Maintenance::RecoverMissingFolio.call(
          booking: @booking,
          hotel: @hotel,
          actor: @actor,
          night_audit: @night_audit,
          reason: @reason
        )
        raise recovery.error unless recovery.success?

        evaluation = evaluate(:post_close)
        NightAudits::Resolutions::RefreshSnapshot.call!(
          night_audit: @night_audit,
          business_date_record: current_business_date,
          evaluation: evaluation
        )
        record_resolution_log!(recovery.folio)

        success(folio: recovery.folio, evaluation: evaluation)
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
        blocker_booking_ids: -> { missing_folio_booking_ids },
        blocker_name: "missing folio",
        permission: PERMISSION
      )
    end

    def current_business_date
      @current_business_date ||= @hotel.current_business_date_record
    end

    def missing_folio_booking_ids
      @missing_folio_booking_ids ||= NightAudits::Resolutions::BlockerBookingIds.call(
        night_audit: @night_audit,
        business_date_record: current_business_date,
        blocker_type: BLOCKER_TYPE,
        fresh_blocked_details: fresh_evaluation[:blocked_details]
      )
    end

    def fresh_evaluation
      @fresh_evaluation ||= evaluate(:pre_close)
    end

    def evaluate(phase)
      NightAudits::Evaluate.new(
        hotel: @hotel,
        business_date: @night_audit.business_date,
        phase: phase
      ).call
    end

    def record_resolution_log!(folio)
      NightAudits::RecordLog.call!(
        night_audit: @night_audit,
        user: @actor,
        action_type: "blocker_resolved",
        message: "Recovered missing folio for booking #{@booking.confirmation_token}",
        metadata: {
          blocker_type: BLOCKER_TYPE,
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          booking_folio_id: folio.id,
          reason: @reason
        }
      )
    end

    def success(folio:, evaluation:)
      OpenStruct.new(
        success?: true,
        folio: folio,
        remaining_blockers: evaluation[:blocked_details],
        missing_nightly_charges_remaining?: Array(evaluation[:blocked_details]["missing_nightly_charges"]).any?,
        message: Array(evaluation[:blocked_details]["missing_nightly_charges"]).any? ? "Folio recovered. Missing nightly charges are still detected." : "Folio recovered. Retry Night Audit."
      )
    end

    def failure(error)
      OpenStruct.new(success?: false, folio: nil, remaining_blockers: nil, missing_nightly_charges_remaining?: false, error: error, message: error)
    end
  end
end
