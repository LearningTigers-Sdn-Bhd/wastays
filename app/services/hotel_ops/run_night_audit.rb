module HotelOps
  class RunNightAudit
    Result = Struct.new(:success?, :night_audit, :error, keyword_init: true)

    def initialize(hotel:, business_date:, performed_by_user:, trigger_mode:, notes: nil)
      @hotel = hotel
      @business_date = business_date.to_date
      @performed_by_user = performed_by_user
      @trigger_mode = trigger_mode
      @notes = notes.to_s.strip.presence
    end

    def call
      night_audit = @hotel.night_audits.find_or_initialize_by(business_date: @business_date)
      return Result.new(success?: false, error: "Night audit has already been completed for this date.", night_audit: night_audit) if night_audit.completed?

      ActiveRecord::Base.transaction do
        night_audit.assign_attributes(
          status: "running",
          trigger_mode: @trigger_mode,
          started_at: Time.current,
          completed_at: nil,
          performed_by_user: @performed_by_user,
          notes: @notes,
          force_closed: false
        )
        night_audit.save!

        log_event(night_audit, "process_started", "Night audit process started for business date #{@business_date}")

        pre_evaluation = HotelOps::EvaluateNightAudit.new(hotel: @hotel, business_date: @business_date, phase: :pre_close).call

        if blocked?(pre_evaluation)
          log_blockers(night_audit, pre_evaluation[:blocked_details])
          log_exceptions(night_audit, pre_evaluation[:exceptions])
          persist_financial_summary(night_audit, calculate_financial_totals)

          night_audit.update!(
            status: "blocked",
            completed_at: Time.current,
            summary: pre_evaluation[:summary],
            blocked_details: pre_evaluation[:blocked_details],
            exceptions: pre_evaluation[:exceptions]
          )

          log_event(night_audit, "blocker_found", "Night audit process stopped before posting due to blockers")
          next
        end

        Bookings::ProcessNoShows.call(night_audit: night_audit, user: @performed_by_user)
        Folios::PostNightlyCharges.call(night_audit: night_audit, user: @performed_by_user)

        # Use the evaluation service to get blockers and exceptions
        evaluation = HotelOps::EvaluateNightAudit.new(hotel: @hotel, business_date: @business_date, phase: :post_close).call
        
        log_blockers(night_audit, evaluation[:blocked_details])
        log_exceptions(night_audit, evaluation[:exceptions])

        # Calculate and persist financial summary
        financial_totals = calculate_financial_totals
        persist_financial_summary(night_audit, financial_totals)

        night_audit.update!(
          status: blocked?(evaluation) ? "blocked" : "completed",
          completed_at: Time.current,
          summary: evaluation[:summary],
          blocked_details: evaluation[:blocked_details],
          exceptions: evaluation[:exceptions]
        )

        final_status = night_audit.status
        log_event(night_audit, final_status == "completed" ? "completed" : "blocker_found", "Night audit process finished with status: #{final_status}")
      end

      Result.new(success?: night_audit.completed?, night_audit: night_audit)
    rescue StandardError => e
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

    def blocked?(evaluation)
      evaluation[:blocked_details].values.flatten.any?
    end

    def persist_financial_summary(night_audit, totals)
      summary = night_audit.financial_summary || night_audit.build_financial_summary
      summary.assign_attributes(totals)
      summary.save!
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

      failed_audit
    end
  end
end
