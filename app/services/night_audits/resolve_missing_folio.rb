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

      recovery = Folios::RecoverMissingFolio.call(
        booking: @booking,
        hotel: @hotel,
        actor: @actor,
        night_audit: @night_audit,
        reason: @reason
      )
      return failure(recovery.error) unless recovery.success?

      evaluation = NightAudits::Evaluate.new(
        hotel: @hotel,
        business_date: @night_audit.business_date,
        phase: :post_close
      ).call

      update_blockers!(evaluation)
      record_resolution_log!(recovery.folio)

      success(folio: recovery.folio, evaluation: evaluation)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate_context
      return "You do not have permission to resolve Night Audit blockers." unless allowed_actor?
      return "Booking does not belong to this hotel." unless @booking.hotel_id == @hotel.id
      return "Night audit is not blocked." unless @night_audit.blocked?
      return "Hotel has no current accounting business date." unless current_business_date
      return "Night audit is not for the current accounting business date." unless current_business_date&.business_date == @night_audit.business_date
      return "Business date must be audit blocked before resolving blockers." unless current_business_date.audit_blocked?
      return "Booking is not in the missing folio blocker list." unless missing_folio_booking_ids.include?(@booking.id)

      nil
    end

    def allowed_actor?
      return true if @actor&.respond_to?(:superadmin?) && @actor.superadmin?
      return false unless @actor&.respond_to?(:has_permission?)

      @actor.has_permission?(PERMISSION, hotel: @hotel)
    end

    def current_business_date
      @current_business_date ||= @hotel.current_business_date_record
    end

    def missing_folio_booking_ids
      @missing_folio_booking_ids ||= begin
        stored_ids = Array(@night_audit.blocked_details.to_h[BLOCKER_TYPE]).filter_map { |item| item["booking_id"] || item[:booking_id] }
        snapshot_ids = Array(current_business_date&.blockers_snapshot.to_h[BLOCKER_TYPE]).filter_map { |item| item["booking_id"] || item[:booking_id] }
        fresh_ids = Array(fresh_evaluation[:blocked_details][BLOCKER_TYPE]).filter_map { |item| item["booking_id"] }

        (stored_ids + snapshot_ids + fresh_ids).map(&:to_i).uniq
      end
    end

    def fresh_evaluation
      @fresh_evaluation ||= NightAudits::Evaluate.new(
        hotel: @hotel,
        business_date: @night_audit.business_date,
        phase: :pre_close
      ).call
    end

    def update_blockers!(evaluation)
      @night_audit.update!(
        blocked_details: evaluation[:blocked_details],
        exceptions: evaluation[:exceptions],
        summary: @night_audit.summary.to_h.merge(evaluation[:summary])
      )

      current_business_date.update!(blockers_snapshot: evaluation[:blocked_details])
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
