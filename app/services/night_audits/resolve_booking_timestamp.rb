# frozen_string_literal: true

require "ostruct"

module NightAudits
  class ResolveBookingTimestamp
    TYPES = {
      "checked_in_missing_timestamp" => { status: "checked_in", attribute: :checked_in_at, label: "check-in" },
      "completed_missing_timestamp" => { status: "completed", attribute: :checked_out_at, label: "check-out" }
    }.freeze
    PERMISSION = "manage_night_audit"

    def self.call(night_audit:, booking:, actor:, blocker_type:, timestamp:, reason:)
      new(night_audit:, booking:, actor:, blocker_type:, timestamp:, reason:).call
    end

    def initialize(night_audit:, booking:, actor:, blocker_type:, timestamp:, reason:)
      @night_audit = night_audit
      @booking = booking
      @actor = actor
      @hotel = night_audit.hotel
      @blocker_type = blocker_type.to_s
      @definition = TYPES[@blocker_type]
      @timestamp = timestamp
      @reason = reason.to_s.strip
    end

    def call
      return failure("Unsupported timestamp blocker.") unless @definition
      return failure("Manage bookings permission is required to correct booking timestamps.") unless manage_bookings?
      return failure("A correction reason is required.") if @reason.blank?
      return failure("A timestamp is required.") if @timestamp.blank?

      error = validate_context
      return failure(error) if error.present?

      value = @timestamp.respond_to?(:in_time_zone) ? @timestamp : Time.zone.parse(@timestamp.to_s)
      return failure("Timestamp is invalid.") unless value

      ActiveRecord::Base.transaction do
        @booking.with_lock do
          @booking.reload
          raise "Booking no longer requires this timestamp correction." unless @booking.status == @definition[:status] && @booking.public_send(@definition[:attribute]).nil?

          @booking.update!(@definition[:attribute] => value)
          Bookings::RecordAuditLog.call!(
            auditable: @booking,
            user: @actor,
            action_type: "update",
            source: "night_audit",
            old_value: { @definition[:attribute].to_s => nil },
            new_value: { @definition[:attribute].to_s => value },
            reason: @reason,
            metadata: { night_audit_id: @night_audit.id, blocker_type: @blocker_type }
          )
        end

        evaluation = NightAudits::Evaluate.new(hotel: @hotel, business_date: @night_audit.business_date, phase: :pre_close).call
        NightAudits::Resolutions::RefreshSnapshot.call!(night_audit: @night_audit, business_date_record: current_business_date, evaluation: evaluation)
        record_resolution_log!(value)
      end

      OpenStruct.new(success?: true, booking: @booking.reload, message: "Booking #{@definition[:label]} timestamp corrected.")
    rescue ArgumentError, TypeError
      failure("Timestamp is invalid.")
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
        blocker_name: @definition[:label],
        permission: PERMISSION,
        mode: :preparation
      )
    end

    def current_business_date
      @current_business_date ||= @hotel.current_business_date_record
    end

    def blocker_booking_ids
      evaluation = NightAudits::Evaluate.new(hotel: @hotel, business_date: @night_audit.business_date, phase: :pre_close).call
      Array(evaluation[:blocked_details][@blocker_type]).filter_map { |item| item["booking_id"] || item[:booking_id] }.map(&:to_i)
    end

    def record_resolution_log!(value)
      NightAudits::RecordLog.call!(
        night_audit: @night_audit,
        user: @actor,
        action_type: "blocker_resolved",
        message: "Corrected #{@definition[:label]} timestamp for booking #{@booking.confirmation_token}",
        metadata: {
          blocker_type: @blocker_type,
          booking_id: @booking.id,
          reason: @reason,
          before: { @definition[:attribute] => nil },
          after: { @definition[:attribute] => value }
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
