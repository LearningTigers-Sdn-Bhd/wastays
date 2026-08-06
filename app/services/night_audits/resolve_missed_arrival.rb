# frozen_string_literal: true

require "ostruct"

module NightAudits
  class ResolveMissedArrival
    BLOCKER_TYPE = "missed_arrival_not_resolved"
    PERMISSION = "manage_night_audit"

    def self.call(night_audit:, booking:, actor:, reason:)
      new(night_audit: night_audit, booking: booking, actor: actor, reason: reason).call
    end

    def initialize(night_audit:, booking:, actor:, reason:)
      @night_audit = night_audit
      @booking = booking
      @actor = actor
      @hotel = night_audit.hotel
      @reason = reason.to_s.strip
    end

    def call
      return failure("Manage bookings permission is required to resolve a missed arrival.") unless manage_bookings?

      error = validate_context
      return failure(error) if error.present?
      return failure("A no-show reason is required.") if @reason.blank?

      ActiveRecord::Base.transaction do
        detect_if_needed!
        result = Bookings::FinalizeNoShow.call(
          booking: @booking,
          user: @actor,
          night_audit: @night_audit,
          reason: @reason
        )
        raise result.error unless result.success?

        evaluation = NightAudits::Evaluate.new(
          hotel: @hotel,
          business_date: @night_audit.business_date,
          phase: :pre_close
        ).call
        NightAudits::Resolutions::RefreshSnapshot.call!(
          night_audit: @night_audit,
          business_date_record: current_business_date,
          evaluation: evaluation
        )
        record_resolution_log!
      end

      OpenStruct.new(success?: true, booking: @booking.reload, message: "Booking marked as no-show. Night Audit readiness refreshed.")
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
        blocker_name: "missed arrival",
        permission: PERMISSION,
        mode: :preparation
      )
    end

    def current_business_date
      @current_business_date ||= @hotel.current_business_date_record
    end

    def blocker_booking_ids
      @blocker_booking_ids ||= Array(fresh_evaluation[:blocked_details][BLOCKER_TYPE]).filter_map do |item|
        item["booking_id"] || item[:booking_id]
      end.map(&:to_i)
    end

    def fresh_evaluation
      @fresh_evaluation ||= NightAudits::Evaluate.new(
        hotel: @hotel,
        business_date: @night_audit.business_date,
        phase: :pre_close
      ).call
    end

    def detect_if_needed!
      @booking.with_lock do
        @booking.reload
        next if @booking.status == "no_show_detected"
        raise "Booking is no longer an unresolved missed arrival." unless @booking.status == "confirmed"

        @booking.transition_status_to!(
          "no_show_detected",
          event: "detect_no_show",
          attributes: { no_show_detected_business_date: @night_audit.business_date }
        )
        Bookings::RecordAuditLog.call!(
          auditable: @booking,
          user: @actor,
          action_type: "status_change",
          source: "night_audit",
          old_value: { "status" => "confirmed" },
          new_value: { "status" => "no_show_detected" },
          reason: @reason,
          metadata: {
            event: "detect_no_show",
            night_audit_id: @night_audit.id,
            business_date: @night_audit.business_date.iso8601
          }
        )
      end
    end

    def record_resolution_log!
      NightAudits::RecordLog.call!(
        night_audit: @night_audit,
        user: @actor,
        action_type: "blocker_resolved",
        message: "Resolved missed arrival for booking #{@booking.confirmation_token}",
        metadata: {
          blocker_type: BLOCKER_TYPE,
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          resolution: "marked_no_show",
          reason: @reason,
          before: { status: "confirmed" },
          after: { status: "no_show" }
        }
      )
    end

    def failure(error)
      OpenStruct.new(success?: false, booking: @booking, error: error, message: error)
    end

    def manage_bookings?
      return true if @actor&.respond_to?(:superadmin?) && @actor.superadmin?

      @actor&.respond_to?(:has_permission?) && @actor.has_permission?("manage_bookings", hotel: @hotel)
    end
  end
end
