# frozen_string_literal: true

module Onboarding
  class ApproveOnboarding
    Result = ApplicationResult.define(:submission, :readiness)

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:)
      @hotel = hotel
      @actor = actor
    end

    def call
      submission = nil
      readiness = nil
      error = nil

      Hotel.transaction do
        @hotel.lock!
        submission = @hotel.onboarding_submissions.find_by(status: "pending_review")
        unless submission && @hotel.status == "pending_review"
          error = "This property is not awaiting onboarding review."
          raise ActiveRecord::Rollback
        end

        comparison = CompareSubmission.call(hotel: @hotel, submission:)
        unless comparison.success? && comparison.unchanged
          error = comparison.error || "The property setup changed after submission. Request changes before approving it."
          raise ActiveRecord::Rollback
        end

        today = Date.current
        extension = ExtendAvailability.call(hotel: @hotel, submission:, actor: @actor, today:)
        unless extension.success?
          error = extension.error
          raise ActiveRecord::Rollback
        end

        rates_coverage = Rates::SetupCoverage.call(hotel: @hotel, start_date: today, end_date: today + 364.days)
        readiness = Readiness.new(hotel: @hotel, rates_coverage:).call
        unless readiness.ready
          error = "The property is no longer ready to launch. Request changes instead."
          raise ActiveRecord::Rollback
        end

        transition = TransitionLifecycle.new(
          hotel: @hotel, to: "ready_to_launch", actor: @actor,
          metadata: { submission_id: submission.id }
        ).call
        unless transition.success?
          error = transition.error
          raise ActiveRecord::Rollback
        end

        submission.update!(status: "approved", reviewed_by: @actor, reviewed_at: Time.current)
        CreateDeliveries.for_owners(submission, "owner_launch_decision_required")
      end

      return Result.failure(error, submission:, readiness:) if error

      DispatchPendingDeliveriesJob.perform_later(submission.id) if submission
      Result.success(submission:, readiness:)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence, submission:, readiness:)
    end
  end
end
