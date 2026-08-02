# frozen_string_literal: true

module NightAudits
  class StartManualReview
    Result = Data.define(
      :night_audit,
      :evaluation,
      :due_outs_detected_count,
      :missed_arrivals_detected_count,
      :failures,
      :error
    ) do
      def success? = error.blank?
      def detected_count = due_outs_detected_count.to_i + missed_arrivals_detected_count.to_i
    end

    def self.call(hotel:, business_date:, actor:)
      new(hotel:, business_date:, actor:).call
    end

    def initialize(hotel:, business_date:, actor:)
      @hotel = hotel
      @business_date = business_date.to_date
      @actor = actor
    end

    def call
      return failure("You do not have permission to start Night Audit review.") unless permitted?
      return failure(unclosable_message) unless @hotel.can_audit_date?(@business_date)

      audit = claim_manual_preparation
      return failure("Night Audit review cannot start while the audit is #{audit.status}.", night_audit: audit) unless audit.preparing?

      due_outs = NightAudits::DetectDueOuts.call(night_audit: audit, user: @actor)
      missed_arrivals = NightAudits::DetectMissedArrivals.call(night_audit: audit, user: @actor)
      failures = Array(due_outs.failed) + Array(missed_arrivals.failed)
      evaluation = refresh_snapshot!(audit, due_outs:, missed_arrivals:, failures:)

      record_review_log!(audit, due_outs:, missed_arrivals:, failures:)
      record_detection_logs!(audit, due_outs:, missed_arrivals:)
      record_failure_logs!(audit, failures)

      Result.new(
        night_audit: audit,
        evaluation: evaluation,
        due_outs_detected_count: due_outs.detected.size,
        missed_arrivals_detected_count: missed_arrivals.detected_count,
        failures: failures,
        error: nil
      )
    rescue ActiveRecord::RecordInvalid, HotelBusinessDate::InvalidTransition, StandardError => error
      failure(error.message)
    end

    private

    def claim_manual_preparation
      record = @hotel.current_business_date_record ||
        HotelBusinessDate.initialize_for_hotel!(hotel: @hotel, date: @business_date)

      record.with_lock do
        record.reload
        unless record.current? && record.open? && record.business_date == @business_date
          raise HotelBusinessDate::InvalidTransition, "Business date must be current and open to start Night Audit review."
        end

        prepared = NightAudits::StartPreparation.call(hotel: @hotel, business_date: @business_date, trigger_mode: "manual")
        audit = prepared.night_audit
        audit.update!(trigger_mode: "manual", performed_by_user: @actor) if audit.preparing?
        audit
      end
    end

    def refresh_snapshot!(audit, due_outs:, missed_arrivals:, failures:)
      evaluation = NightAudits::Evaluate.new(hotel: @hotel, business_date: @business_date, phase: :pre_close).call
      blocked_details = evaluation[:blocked_details].deep_dup
      failures.any? ? blocked_details["detection_failures"] = failures : blocked_details.delete("detection_failures")
      evaluation = evaluation.merge(blocked_details: blocked_details)

      audit.update!(
        blocked_details: blocked_details,
        exceptions: evaluation[:exceptions],
        summary: audit.summary.to_h.merge(
          evaluation[:summary],
          "manual_review" => {
            "started_by_user_id" => @actor.id,
            "started_at" => Time.current.iso8601,
            "due_outs_detected_count" => due_outs.detected.size,
            "missed_arrivals_detected_count" => missed_arrivals.detected_count,
            "detection_failure_count" => failures.size
          }
        )
      )
      evaluation
    end

    def record_review_log!(audit, due_outs:, missed_arrivals:, failures:)
      NightAudits::RecordLog.call!(
        night_audit: audit,
        user: @actor,
        action_type: "review_started",
        message: "Night Audit review started for #{@business_date}",
        metadata: {
          business_date: @business_date.iso8601,
          due_outs_detected_count: due_outs.detected.size,
          missed_arrivals_detected_count: missed_arrivals.detected_count,
          detection_failure_count: failures.size
        }
      )
    end

    def record_detection_logs!(audit, due_outs:, missed_arrivals:)
      due_outs.detected.each do |item|
        record_detection_log!(audit, item, from: "checked_in", to: "due_out_detected", reason: "Checkout date passed without checkout")
      end
      missed_arrivals.bookings.each do |booking|
        record_detection_log!(
          audit,
          { "booking_id" => booking.id, "confirmation_token" => booking.confirmation_token },
          from: "confirmed",
          to: "no_show_detected",
          reason: "Arrival grace period passed without check-in"
        )
      end
    end

    def record_detection_log!(audit, item, from:, to:, reason:)
      NightAudits::RecordLog.call!(
        night_audit: audit,
        user: @actor,
        action_type: "item_detected",
        message: "Booking #{item['confirmation_token']} changed from #{from} to #{to}",
        metadata: {
          blocker_type: to,
          booking_id: item["booking_id"],
          confirmation_token: item["confirmation_token"],
          business_date: @business_date.iso8601,
          reason: reason,
          before: { status: from },
          after: { status: to }
        }
      )
    end

    def record_failure_logs!(audit, failures)
      failures.each do |item|
        NightAudits::RecordLog.call!(
          night_audit: audit,
          user: @actor,
          action_type: "item_failed",
          message: "Could not classify booking #{item['confirmation_token']} during Night Audit review",
          metadata: item.merge("business_date" => @business_date.iso8601)
        )
      end
    end

    def permitted?
      return true if @actor&.respond_to?(:superadmin?) && @actor.superadmin?

      @actor&.respond_to?(:has_permission?) && @actor.has_permission?("manage_night_audit", hotel: @hotel)
    end

    def unclosable_message
      window = @hotel.business_day_window_for(@business_date)
      "Business date #{@business_date} can be reviewed after #{window.end.strftime('%I:%M %p')}."
    end

    def failure(error, night_audit: nil)
      Result.new(
        night_audit: night_audit,
        evaluation: nil,
        due_outs_detected_count: 0,
        missed_arrivals_detected_count: 0,
        failures: [],
        error: error
      )
    end
  end
end
