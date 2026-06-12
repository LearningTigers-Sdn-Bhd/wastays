module HotelOps
  class RunNightAudit
    Result = Struct.new(:success?, :night_audit, :error, keyword_init: true)

    def initialize(hotel:, business_date:, performed_by_user:, trigger_mode:, notes: nil, allow_unclosable_date: false, force_roll: false)
      @hotel = hotel
      @business_date = business_date.to_date
      @performed_by_user = performed_by_user
      @trigger_mode = trigger_mode
      @notes = notes.to_s.strip.presence
      @allow_unclosable_date = Rails.env.development? && allow_unclosable_date
      @force_roll = force_roll
    end

    def call
      night_audit = @hotel.night_audits.find_or_initialize_by(business_date: @business_date)
      return Result.new(success?: false, error: "Night audit has already been completed for this date.", night_audit: night_audit) if night_audit.completed?

      unless @allow_unclosable_date || @hotel.can_audit_date?(@business_date)
        window = @hotel.business_day_window_for(@business_date)
        error = "Business date #{@business_date} cannot be audited yet. The business day ends at #{window.end.strftime('%I:%M %p')}."
        night_audit = persist_failure(night_audit, error) if night_audit.persisted? && night_audit.pending?
        return Result.new(success?: false, error: error, night_audit: night_audit)
      end

      business_date, claim_error = claim_business_date
      return Result.new(success?: false, error: claim_error, night_audit: night_audit) if claim_error

      night_audit.assign_attributes(
        status: "running",
        trigger_mode: @trigger_mode,
        started_at: Time.current,
        completed_at: nil,
        performed_by_user: @performed_by_user,
        notes: @notes,
        force_closed: @force_roll
      )
      night_audit.save!

      log_event(night_audit, "process_started", "Night audit process started for business date #{@business_date}")
      record_night_audit_event!(night_audit, business_date, "night_audit_started", "Night audit started")
      record_night_audit_event!(night_audit, business_date, "business_date_audit_started", "Business date moved to audit_running")

      no_show_result = Bookings::ProcessNoShowReviews.call(night_audit: night_audit, user: @performed_by_user)
      night_audit.night_audit_logs.where(action_type: "process_started").order(:id).last&.update!(
        metadata: {
          reviewed_no_show_count: no_show_result.reviewed_count,
          finalized_no_show_count: no_show_result.finalized_count
        }
      )

      pre_evaluation = HotelOps::EvaluateNightAudit.new(hotel: @hotel, business_date: @business_date, phase: :pre_close).call

      if blocked?(pre_evaluation) && !@force_roll
        log_blockers(night_audit, pre_evaluation[:blocked_details])
        log_exceptions(night_audit, pre_evaluation[:exceptions])

        ActiveRecord::Base.transaction do
          persist_financial_summary(night_audit, calculate_financial_totals)

          night_audit.update!(
            status: "blocked",
            completed_at: Time.current,
            summary: pre_evaluation[:summary],
            blocked_details: pre_evaluation[:blocked_details],
            exceptions: pre_evaluation[:exceptions]
          )
          business_date.block_audit!(blockers: pre_evaluation[:blocked_details])
        end

        log_event(night_audit, "blocker_found", "Night audit process stopped before posting due to blockers")
        record_night_audit_event!(night_audit, business_date, "night_audit_blocked", "Night audit blocked before posting", blockers: pre_evaluation[:blocked_details])
        record_night_audit_event!(night_audit, business_date, "business_date_audit_blocked", "Business date moved to audit_blocked", blockers: pre_evaluation[:blocked_details])
        return Result.new(success?: night_audit.completed?, night_audit: night_audit)
      end

      Folios::PostNightlyCharges.call(night_audit: night_audit, user: @performed_by_user)

      # Use the evaluation service to get blockers and exceptions
      evaluation = HotelOps::EvaluateNightAudit.new(hotel: @hotel, business_date: @business_date, phase: :post_close).call

      log_blockers(night_audit, evaluation[:blocked_details])
      log_exceptions(night_audit, evaluation[:exceptions])

      # Calculate and persist financial summary
      financial_totals = calculate_financial_totals

      next_business_date = nil

      ActiveRecord::Base.transaction do
        persist_financial_summary(night_audit, financial_totals)

        is_blocked = blocked?(evaluation)
        final_status = (is_blocked && !@force_roll) ? "blocked" : "completed"

        night_audit.update!(
          status: final_status,
          completed_at: Time.current,
          summary: evaluation[:summary],
          blocked_details: evaluation[:blocked_details],
          exceptions: evaluation[:exceptions],
          force_closed: @force_roll && is_blocked
        )

        if final_status == "completed"
          if @force_roll && is_blocked
            business_date.force_close!
          else
            business_date.complete_audit!
          end

          next_business_date = business_date.open_next_business_date!
          Financials::CreateJournalBatch.call(hotel: @hotel, business_date: @business_date)

          event_type = @force_roll && is_blocked ? "night_audit_force_rolled" : "night_audit_completed"
          reason = @force_roll && is_blocked ? "Night audit force-rolled with blockers" : "Night audit completed"

          persist_night_audit_event!(night_audit, business_date, event_type, reason, financial_totals: financial_totals)
          persist_night_audit_event!(night_audit, business_date, "business_date_closed", "Business date moved to closed")
          persist_night_audit_event!(night_audit, next_business_date, "business_date_opened", "Next business date opened after night audit", opened_business_date: next_business_date.business_date)
        else
          business_date.block_audit!(blockers: evaluation[:blocked_details])
        end
      end

      final_status = night_audit.status
      log_event(night_audit, final_status == "completed" ? "completed" : "blocker_found", "Night audit process finished with status: #{final_status}")
      if final_status != "completed"
        record_night_audit_event!(night_audit, business_date, "night_audit_blocked", "Night audit blocked after posting", blockers: evaluation[:blocked_details])
        record_night_audit_event!(night_audit, business_date, "business_date_audit_blocked", "Business date moved to audit_blocked", blockers: evaluation[:blocked_details])
      end

      Result.new(success?: night_audit.completed?, night_audit: night_audit)
    rescue StandardError => e
      block_business_date_after_failure(business_date, e.message) if defined?(business_date) && business_date
      night_audit = persist_failure(night_audit, e.message)
      Result.new(success?: false, night_audit: night_audit, error: e.message)
    end

    private

    def log_event(night_audit, action_type, message, metadata = {})
      night_audit.night_audit_logs.create!(
        hotel: @hotel,
        user: @performed_by_user,
        action_type: action_type,
        message: message,
        metadata: metadata
      )
    end

    def log_blockers(night_audit, blocked_details)
      blocked_details.each do |type, items|
        next if items.empty?

        log_event(night_audit, "blocker_found", "Found #{items.count} blockers of type: #{type.humanize}", { type: type, count: items.count, items: items })
      end
    end

    def log_exceptions(night_audit, exceptions)
      exceptions.each do |type, items|
        next if items.empty?

        log_event(night_audit, "exception_found", "Found #{items.count} exceptions of type: #{type.humanize}", { type: type, count: items.count, items: items })
      end
    end

    def calculate_financial_totals
      HotelOps::CalculateBusinessDayFinancials.call(hotel: @hotel, business_date: @business_date)
    end

    def claim_business_date
      business_date = HotelBusinessDate.for_hotel_date!(hotel: @hotel, date: @business_date)
      business_date.with_lock do
        return [ nil, "Night audit is already running for this date." ] if business_date.audit_running?
        if business_date.closed? || business_date.force_closed?
          return [ nil, "Night audit has already been closed for this date." ]
        end

        business_date.start_audit!
        [ business_date, nil ]
      end
    end

    def blocked?(evaluation)
      evaluation[:blocked_details].values.flatten.any?
    end

    def persist_financial_summary(night_audit, totals)
      summary = night_audit.financial_summary || night_audit.build_financial_summary
      summary.assign_attributes(totals)
      summary.save!
    end

    def block_business_date_after_failure(business_date, error_message)
      business_date.reload
      return unless business_date.audit_running?

      business_date.block_audit!(blockers: { "audit_failure" => [ { "message" => error_message } ] })
    rescue StandardError => e
      Rails.logger.error("Failed to mark business date blocked after night audit failure: #{e.message}")
    end

    def persist_failure(night_audit, error_message)
      failed_audit = night_audit.presence || @hotel.night_audits.find_or_initialize_by(business_date: @business_date)
      failed_audit.assign_attributes(
        status: "failed",
        trigger_mode: @trigger_mode,
        performed_by_user: @performed_by_user,
        completed_at: Time.current,
        notes: @notes,
        force_closed: false
      )
      failed_audit.started_at ||= Time.current
      failed_audit.summary ||= {}
      failed_audit.blocked_details ||= {}
      failed_audit.exceptions ||= {}
      failed_audit.save!(validate: false)

      log_event(failed_audit, "failed", "Night audit failed: #{error_message}", { error: error_message })
      business_date = HotelBusinessDate.find_by(hotel: @hotel, business_date: @business_date)
      record_night_audit_event!(failed_audit, business_date, "night_audit_failed", "Night audit failed", error: error_message)
      if business_date&.audit_blocked?
        record_night_audit_event!(failed_audit, business_date, "business_date_audit_blocked", "Business date moved to audit_blocked", error: error_message)
      end

      failed_audit
    end

    def record_night_audit_event!(night_audit, business_date, event_type, reason, metadata = {})
      persist_night_audit_event!(night_audit, business_date, event_type, reason, metadata)
    rescue StandardError => e
      Rails.logger.error("Failed to record financial audit event #{event_type} for night audit #{night_audit.id}: #{e.message}")
    end

    def persist_night_audit_event!(night_audit, business_date, event_type, reason, metadata = {})
      FinancialControls::AuditEventRecorder.call!(
        hotel: @hotel,
        business_date: business_date&.business_date || @business_date,
        event_type: event_type,
        source: "night_audit",
        actor: @performed_by_user,
        night_audit: night_audit,
        hotel_business_date: business_date,
        reason: reason,
        metadata: metadata.merge(
          night_audit_status: night_audit.status,
          trigger_mode: @trigger_mode
        )
      )
    end
  end
end
