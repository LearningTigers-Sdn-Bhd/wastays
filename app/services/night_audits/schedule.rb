# frozen_string_literal: true

module NightAudits
  class Schedule
    Result = Data.define(:night_audit, :evaluation, :enqueued, :error)

    def self.call(hotel:, business_date:, performed_by_user:, trigger_mode:, notes: nil, allow_unclosable_date: false, force_roll: false)
      new(
        hotel: hotel,
        business_date: business_date,
        performed_by_user: performed_by_user,
        trigger_mode: trigger_mode,
        notes: notes,
        allow_unclosable_date: allow_unclosable_date,
        force_roll: force_roll
      ).call
    end

    def initialize(hotel:, business_date:, performed_by_user:, trigger_mode:, notes:, allow_unclosable_date:, force_roll:)
      @hotel = hotel
      @business_date = business_date.to_date
      @performed_by_user = performed_by_user
      @trigger_mode = trigger_mode
      @notes = notes.to_s.strip.presence
      @allow_unclosable_date = allow_unclosable_date
      @force_roll = force_roll
    end

    def call
      unless closable?
        return Result.new(
          night_audit: @hotel.night_audits.find_by(business_date: @business_date),
          evaluation: nil,
          enqueued: false,
          error: "Business date #{@business_date} cannot be audited yet."
        )
      end

      audit, evaluation, should_enqueue = schedule_under_lock
      return Result.new(night_audit: audit, evaluation: evaluation, enqueued: false, error: nil) unless should_enqueue

      NightAudits::RunJob.perform_later(
        audit.id,
        @performed_by_user&.id,
        allow_unclosable_date: @allow_unclosable_date,
        force_roll: @force_roll
      )
      Result.new(night_audit: audit, evaluation: evaluation, enqueued: true, error: nil)
    rescue ActiveRecord::RecordNotUnique
      existing_result(@hotel.night_audits.find_by!(business_date: @business_date))
    end

    private

    def closable?
      (Rails.env.development? && @allow_unclosable_date) || @hotel.can_audit_date?(@business_date)
    end

    def schedule_under_lock
      record = @hotel.current_business_date_record ||
        HotelBusinessDate.initialize_for_hotel!(hotel: @hotel, date: @business_date)

      record.with_lock do
        record.reload
        raise HotelBusinessDate::InvalidTransition, "Business date #{@business_date} is not current." unless record.current? && record.business_date == @business_date

        audit = @hotel.night_audits.find_by(business_date: @business_date)
        return [ audit, nil, false ] if audit&.running? || audit&.pending? || audit&.completed?
        return [ audit, nil, false ] if scheduled_takeover_of_manual_review?(audit)

        phase = audit&.blocked? ? :post_close : :pre_close
        evaluation = NightAudits::Evaluate.new(hotel: @hotel, business_date: @business_date, phase: phase).call
        if blocked?(evaluation) && !@force_roll
          audit = persist_not_ready(audit, evaluation)
          return [ audit, evaluation, false ]
        end

        [ persist_pending(audit, evaluation), evaluation, true ]
      end
    end

    def persist_pending(audit, evaluation)
      audit ||= @hotel.night_audits.build(business_date: @business_date)
      audit.assign_attributes(
        status: "pending",
        trigger_mode: @trigger_mode,
        started_at: nil,
        completed_at: nil,
        performed_by_user: @performed_by_user,
        notes: @notes,
        blocked_details: evaluation[:blocked_details],
        exceptions: evaluation[:exceptions],
        summary: audit.summary.to_h.merge(evaluation[:summary]),
        force_closed: @force_roll
      )
      audit.save!
      audit
    end

    def persist_not_ready(audit, evaluation)
      audit ||= @hotel.night_audits.build(business_date: @business_date)
      return audit.tap { |record| refresh_existing_snapshot(record, evaluation) } if audit.blocked? || audit.failed?

      audit.assign_attributes(
        status: "preparing",
        trigger_mode: @trigger_mode,
        started_at: nil,
        completed_at: nil,
        performed_by_user: nil,
        notes: @notes,
        blocked_details: evaluation[:blocked_details],
        exceptions: evaluation[:exceptions],
        summary: audit.summary.to_h.merge(evaluation[:summary]),
        force_closed: false
      )
      audit.save!
      audit
    end

    def refresh_existing_snapshot(audit, evaluation)
      audit.update!(
        blocked_details: evaluation[:blocked_details],
        exceptions: evaluation[:exceptions],
        summary: audit.summary.to_h.merge(evaluation[:summary])
      )
    end

    def existing_result(audit)
      Result.new(night_audit: audit, evaluation: nil, enqueued: false, error: nil)
    end

    def blocked?(evaluation)
      evaluation[:blocked_details].values.flatten.any?
    end

    def scheduled_takeover_of_manual_review?(audit)
      @trigger_mode == "scheduled" && audit&.preparing? && audit.trigger_mode == "manual" && audit.performed_by_user_id.present?
    end
  end
end
