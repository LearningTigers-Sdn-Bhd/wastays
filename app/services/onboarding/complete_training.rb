# frozen_string_literal: true

module Onboarding
  class CompleteTraining
    Result = ApplicationResult.define(:hotel, :submission, :readiness)
    DECISIONS = %w[keep reset].freeze

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:, decision:)
      @hotel = hotel
      @actor = actor
      @decision = decision.to_s
    end

    def call
      return failure("Choose whether to continue with current data or start fresh.") unless @decision.in?(DECISIONS)

      submission = nil
      readiness = nil
      error = nil
      already_completed = false

      Hotel.transaction do
        @hotel.lock!
        submission = @hotel.onboarding_submissions.find_by(status: "approved")

        if completed_with_same_decision?
          already_completed = true
          next
        elsif @hotel.status == "live"
          error = "This property has already launched with a different launch decision."
          raise ActiveRecord::Rollback
        elsif submission.blank? || @hotel.status != "ready_to_launch"
          error = "This property is not awaiting a launch decision."
          raise ActiveRecord::Rollback
        elsif conflicting_decision?
          error = "A different launch decision has already been recorded."
          raise ActiveRecord::Rollback
        elsif reset_in_progress_for_keep?
          error = "PMS activity is currently being cleared. Wait for it to finish before continuing."
          raise ActiveRecord::Rollback
        elsif @decision == "reset" && @hotel.training_reset_state != "processing"
          error = "PMS activity must finish clearing before the property can launch."
          raise ActiveRecord::Rollback
        end

        rates_coverage = Rates::SetupCoverage.call(hotel: @hotel)
        readiness = Readiness.new(hotel: @hotel, rates_coverage:).call
        unless readiness.ready
          error = "The property is no longer ready to launch. Contact WAStays support."
          raise ActiveRecord::Rollback
        end

        current = SubmissionSnapshot.call(hotel: @hotel, rates_coverage:)
        unless ActiveSupport::SecurityUtils.secure_compare(current.digest, submission.configuration_digest)
          error = "The property setup changed after approval. Contact WAStays support before launching."
          raise ActiveRecord::Rollback
        end

        completed_at = Time.current
        @hotel.update!(
          training_data_decision: @decision,
          training_completed_at: completed_at,
          training_completed_by: @actor,
          training_reset_state: nil
        )
        @hotel.onboarding_audit_events.create!(
          user: @actor,
          event_type: decision_event_type,
          metadata: { submission_id: submission.id },
          occurred_at: completed_at
        )

        transition = TransitionLifecycle.new(
          hotel: @hotel, to: "live", actor: @actor,
          metadata: { submission_id: submission.id, training_data_decision: @decision }
        ).call
        unless transition.success?
          error = transition.error
          raise ActiveRecord::Rollback
        end

        @hotel.account.update!(status: "active") unless @hotel.account.status == "active"
        CreateDeliveries.for_owners(submission, "owner_approved")
        CreateDeliveries.for_approval(submission)
      end

      return failure(error, submission:, readiness:) if error

      if submission && !already_completed
        ActiveRecord.after_all_transactions_commit do
          DispatchPendingDeliveriesJob.perform_later(submission.id)
        end
      end
      Result.success(hotel: @hotel, submission:, readiness:)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence, submission:, readiness:)
    end

    private

    def completed_with_same_decision?
      @hotel.status == "live" && @hotel.training_data_decision == @decision
    end

    def conflicting_decision?
      @hotel.training_data_decision.present? && @hotel.training_data_decision != @decision
    end

    def reset_in_progress_for_keep?
      @decision == "keep" && @hotel.training_reset_state.in?(%w[queued processing])
    end

    def decision_event_type
      @decision == "keep" ? "training_keep_selected" : "training_reset_completed"
    end

    def failure(message, submission: nil, readiness: nil)
      Result.failure(message, hotel: @hotel, submission:, readiness:)
    end
  end
end
