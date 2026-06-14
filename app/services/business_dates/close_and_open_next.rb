# frozen_string_literal: true

module BusinessDates
  class CloseAndOpenNext < BaseTransition
    FORCE_CLOSE_PERMISSION = "override_financial_date_lock".freeze

    Result = Struct.new(:closed_business_date, :next_business_date, keyword_init: true)

    def self.call!(**kwargs)
      new(**kwargs).call!
    end

    def initialize(hotel:, actor: nil, system_context: false, force: false, reason: nil, blockers: nil, night_audit: nil)
      super(hotel: hotel, actor: actor, system_context: system_context)
      @force = force
      @reason = reason.to_s.strip
      @blockers = blockers
      @night_audit = night_audit
    end

    def call!
      @force ? require_force_close_permission! : require_manage_permission!

      with_locked_current do |record|
        verify_current!(record)
        require_status!(record, @force ? "audit_blocked" : "audit_running")
        next_date = record.business_date + 1.day
        reject_existing_next_date!(next_date)

        close!(record)
        next_record = @hotel.hotel_business_dates.create!(
          business_date: next_date,
          status: "open",
          opened_at: Time.current,
          blockers_snapshot: {}
        )
        record_events!(record, next_record)

        Result.new(closed_business_date: record, next_business_date: next_record)
      end
    end

    private

    def require_force_close_permission!
      raise HotelBusinessDate::InvalidTransition, "System context cannot force close a business date." if @system_context
      raise HotelBusinessDate::InvalidTransition, "Force-close reason can't be blank." if @reason.blank?
      return if @actor&.superadmin?
      return if @actor&.has_permission?(FORCE_CLOSE_PERMISSION, hotel: @hotel)

      raise HotelBusinessDate::InvalidTransition, "Actor does not have permission to force close the business date."
    end

    def reject_existing_next_date!(next_date)
      existing = @hotel.hotel_business_dates.find_by(business_date: next_date)
      return unless existing

      raise HotelBusinessDate::InvalidTransition, "Next business date #{next_date} already exists with status #{existing.status}."
    end

    def close!(record)
      now = Time.current
      if @force
        record.update!(
          status: "force_closed",
          closed_at: now,
          force_closed_at: now,
          force_closed_by: @actor,
          force_close_reason: @reason,
          blockers_snapshot: @blockers.presence || record.blockers_snapshot,
          blocked_at: nil
        )
      else
        record.update!(
          status: "closed",
          closed_at: now,
          blockers_snapshot: {},
          blocked_at: nil
        )
      end
    end

    def record_events!(record, next_record)
      FinancialControls::AuditEventRecorder.call!(
        hotel: @hotel,
        business_date: record.business_date,
        event_type: @force ? "business_date_force_closed" : "business_date_closed",
        source: @system_context ? "system" : "night_audit",
        actor: @actor,
        night_audit: @night_audit,
        hotel_business_date: record,
        reason: @reason.presence,
        metadata: { blockers_at_time_of_close: record.blockers_snapshot }
      )
      FinancialControls::AuditEventRecorder.call!(
        hotel: @hotel,
        business_date: next_record.business_date,
        event_type: "business_date_opened",
        source: @system_context ? "system" : "night_audit",
        actor: @actor,
        night_audit: @night_audit,
        hotel_business_date: next_record,
        reason: "Next business date opened after close"
      )
    end
  end
end
