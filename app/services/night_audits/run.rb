module NightAudits
  class Run
    Result = Struct.new(:success?, :night_audit, :error, keyword_init: true)

    def initialize(hotel:, business_date:, performed_by_user:, trigger_mode:, notes: nil, allow_unclosable_date: false, force_roll: false,
      processor: NightAudits::Execution::ProcessBookings, evaluator: NightAudits::Evaluate,
      finalizer: NightAudits::Execution::FinalizeAudit, failure_handler: NightAudits::Execution::PersistFailure)
      @hotel = hotel
      @business_date = business_date.to_date
      @performed_by_user = performed_by_user
      @trigger_mode = trigger_mode
      @notes = notes.to_s.strip.presence
      @allow_unclosable_date = Rails.env.development? && allow_unclosable_date
      @force_roll = force_roll
      @processor = processor
      @evaluator = evaluator
      @finalizer = finalizer
      @failure_handler = failure_handler
    end

    def call
      night_audit = @hotel.night_audits.find_or_initialize_by(business_date: @business_date)
      if @hotel.training_mode?
        return Result.new(success?: false, error: "Night Audit is unavailable while this property is in training.", night_audit: night_audit)
      end
      return Result.new(success?: false, error: "Night audit has already been completed for this date.", night_audit: night_audit) if night_audit.completed?

      unless @allow_unclosable_date || @hotel.can_audit_date?(@business_date)
        window = @hotel.business_day_window_for(@business_date)
        error = "Business date #{@business_date} cannot be audited yet. The business day ends at #{window.end.strftime('%I:%M %p')}."
        night_audit = persist_failure(night_audit, error) if night_audit.persisted? && night_audit.pending?
        return Result.new(success?: false, error: error, night_audit: night_audit)
      end


      current_business_date = @hotel.current_business_date_record ||
        HotelBusinessDate.initialize_for_hotel!(hotel: @hotel, date: @business_date)
      if current_business_date.business_date != @business_date
        error = "Business date #{@business_date} is not the current accounting business date #{current_business_date.business_date}."
        return Result.new(success?: false, error: error, night_audit: night_audit)
      end

      pre_evaluation = evaluate(:pre_close)
      if blocked?(pre_evaluation) && !@force_roll
        persist_preparation!(night_audit, pre_evaluation)
        return Result.new(success?: false, error: "Night audit requires staff resolution.", night_audit: night_audit)
      end

      claim = NightAudits::Execution::ClaimBusinessDate.call(
        hotel: @hotel,
        business_date: @business_date,
        actor: @performed_by_user
      )
      business_date = claim.business_date
      return Result.new(success?: false, error: claim.error, night_audit: night_audit) if claim.error

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

      # Close the small race between the open-date preview and the accounting
      # claim. Once claimed, operational changes are guarded; if something
      # landed just before the claim, release the date without posting.
      claimed_evaluation = evaluate(:pre_close)
      if blocked?(claimed_evaluation) && !@force_roll
        NightAudits::Execution::ReleaseBusinessDate.call!(hotel: @hotel, business_date: @business_date)
        persist_preparation!(night_audit, claimed_evaluation)
        return Result.new(success?: false, error: "Night audit readiness changed before processing.", night_audit: night_audit)
      end

      log_event(night_audit, "process_started", "Night audit process started for business date #{@business_date}")
      record_night_audit_event!(night_audit, business_date, "night_audit_started", "Night audit started")
      record_night_audit_event!(night_audit, business_date, "business_date_audit_started", "Business date moved to audit_running")

      Folios::Charges::PostNightlyCharges.call(night_audit: night_audit, user: @performed_by_user)

      # Use the evaluation service to get blockers and exceptions
      evaluation = evaluate(:post_close)

      log_blockers(night_audit, evaluation[:blocked_details])
      log_exceptions(night_audit, evaluation[:exceptions])

      # Calculate and persist financial summary
      financial_totals = calculate_financial_totals

      finalized = @finalizer.call(
        **finalizer_attributes(
          night_audit: night_audit,
          business_date: business_date,
          evaluation: evaluation,
          financial_totals: financial_totals,
          phase: :post_close
        )
      )
      business_date = finalized.business_date

      final_status = night_audit.status
      log_event(night_audit, final_status == "completed" ? "completed" : "blocker_found", "Night audit process finished with status: #{final_status}")

      Result.new(success?: night_audit.completed?, night_audit: night_audit)
    rescue StandardError => e
      night_audit = @failure_handler.call(
        hotel: @hotel,
        business_date: @business_date,
        business_date_record: (business_date if defined?(business_date)),
        night_audit: night_audit,
        actor: @performed_by_user,
        trigger_mode: @trigger_mode,
        notes: @notes,
        error_message: e.message
      )
      Result.new(success?: false, night_audit: night_audit, error: e.message)
    end

    private

    def log_event(night_audit, action_type, message, metadata = {})
      NightAudits::RecordLog.call!(
        night_audit: night_audit,
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

    def record_result_items(night_audit, action_type, items)
      items.each do |item|
        log_event(night_audit, action_type, item["reason"], { item: item })
      end
    end

    def calculate_financial_totals
      NightAudits::CalculateFinancialSummary.call(hotel: @hotel, business_date: @business_date)
    end

    def persist_failure(night_audit, error_message)
      @failure_handler.call(
        hotel: @hotel,
        business_date: @business_date,
        business_date_record: @hotel.current_business_date_record,
        night_audit: night_audit,
        actor: @performed_by_user,
        trigger_mode: @trigger_mode,
        notes: @notes,
        error_message: error_message
      )
    end

    def persist_preparation!(night_audit, evaluation)
      night_audit.assign_attributes(
        status: "preparing",
        trigger_mode: @trigger_mode,
        started_at: nil,
        completed_at: nil,
        performed_by_user: nil,
        notes: @notes,
        blocked_details: evaluation[:blocked_details],
        exceptions: evaluation[:exceptions],
        summary: night_audit.summary.to_h.merge(evaluation[:summary]),
        force_closed: false
      )
      night_audit.save!
    end

    def blocked?(evaluation)
      evaluation[:blocked_details].values.flatten.any?
    end

    def evaluate(phase)
      @evaluator.new(hotel: @hotel, business_date: @business_date, phase: phase).call
    end

    def finalizer_attributes(night_audit:, business_date:, evaluation:, financial_totals:, phase:)
      {
        hotel: @hotel,
        night_audit: night_audit,
        business_date: business_date,
        evaluation: evaluation,
        financial_totals: financial_totals,
        summary: summary_with_run_results(night_audit, evaluation[:summary]),
        actor: @performed_by_user,
        force_roll: @force_roll,
        notes: @notes,
        trigger_mode: @trigger_mode,
        phase: phase
      }
    end

    def summary_with_run_results(night_audit, summary)
      summary.to_h.merge(
        "run_results" => NightAudits::BuildRunResults.call(night_audit: night_audit)
      )
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
