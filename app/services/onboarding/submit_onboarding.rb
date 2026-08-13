# frozen_string_literal: true

module Onboarding
  class SubmitOnboarding
    Result = ApplicationResult.define(:submission, :readiness)

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:, idempotency_key:)
      @hotel = hotel
      @actor = actor
      @idempotency_key = idempotency_key.to_s
    end

    def call
      return Result.failure("Submission could not be identified. Refresh the page and try again.", submission: nil, readiness: nil) if @idempotency_key.blank?
      existing = OnboardingSubmission.find_by(idempotency_key: @idempotency_key)
      return existing_result(existing) if existing

      submission = nil
      readiness = nil
      error = nil

      Hotel.transaction do
        @hotel.lock!
        pending = @hotel.onboarding_submissions.find_by(status: "pending_review")
        if pending
          submission = pending
          next
        end
        unless LifecycleCompatibility.canonical_status(@hotel.status) == "setup"
          error = "This property cannot be submitted from its current status."
          raise ActiveRecord::Rollback
        end

        readiness = Readiness.new(hotel: @hotel).call
        unless readiness.ready
          error = "Resolve the blocking setup issues before submitting for review."
          raise ActiveRecord::Rollback
        end

        review = UpdateSection.new(
          hotel: @hotel, section_key: "review", state: "complete", actor: @actor,
          metadata: { source: "onboarding_submission" }
        ).call
        unless review.success?
          error = review.error
          raise ActiveRecord::Rollback
        end

        snapshot = SubmissionSnapshot.call(hotel: @hotel)
        submission = @hotel.onboarding_submissions.create!(
          submitted_by: @actor,
          idempotency_key: @idempotency_key,
          status: "pending_review",
          snapshot_version: OnboardingSubmission::SNAPSHOT_VERSION,
          snapshot: snapshot.data,
          readiness_snapshot: serialize_readiness(readiness),
          configuration_digest: snapshot.digest,
          submitted_at: Time.current
        )
        transition = TransitionLifecycle.new(
          hotel: @hotel, to: "pending_review", actor: @actor,
          metadata: { submission_id: submission.id }
        ).call
        unless transition.success?
          error = transition.error
          raise ActiveRecord::Rollback
        end

        CreateDeliveries.for_submission(submission)
      end

      return Result.failure(error, submission:, readiness:) if error

      DispatchPendingDeliveriesJob.perform_later(submission.id) if submission
      Result.success(submission:, readiness:)
    rescue ActiveRecord::RecordNotUnique
      existing = OnboardingSubmission.find_by(idempotency_key: @idempotency_key) || @hotel.onboarding_submissions.find_by(status: "pending_review")
      existing_result(existing)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.to_sentence, submission:, readiness:)
    end

    private

    def existing_result(submission)
      return Result.failure("That submission belongs to another property.", submission:, readiness: nil) if submission&.hotel_id != @hotel.id

      Result.success(submission:, readiness: nil)
    end

    def serialize_readiness(readiness)
      {
        ready: readiness.ready,
        blocking_issues: readiness.blocking_issues.map(&:to_h),
        warnings: readiness.warnings.map(&:to_h)
      }
    end
  end
end
