# frozen_string_literal: true

module Onboarding
  class RequestChanges
    Result = ApplicationResult.define(:submission, :section_keys)

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:, section_keys:, explanation:)
      @hotel = hotel
      @actor = actor
      @section_keys = Array(section_keys).map(&:to_s).uniq
      @explanation = explanation.to_s.strip
    end

    def call
      valid_keys = SectionCatalog.keys - [ "review" ]
      return failure("Select at least one setup section.") if @section_keys.empty?
      return failure("One or more selected sections are not part of onboarding.") unless (@section_keys - valid_keys).empty?
      return failure("Explain what the property owner needs to change.") if @explanation.blank?

      submission = nil
      error = nil
      Hotel.transaction do
        @hotel.lock!
        submission = @hotel.onboarding_submissions.find_by(status: "pending_review")
        unless submission && LifecycleCompatibility.canonical_status(@hotel.status) == "pending_review"
          error = "This property is not awaiting onboarding review."
          raise ActiveRecord::Rollback
        end

        (@section_keys + [ "review" ]).each do |section_key|
          result = UpdateSection.new(
            hotel: @hotel, section_key:, state: "needs_attention", actor: @actor,
            event_type: "changes_requested",
            metadata: { source: "admin_review", explanation: @explanation, submission_id: submission.id }
          ).call
          unless result.success?
            error = result.error
            raise ActiveRecord::Rollback
          end
        end

        transition = TransitionLifecycle.new(
          hotel: @hotel, to: "setup", actor: @actor,
          metadata: { submission_id: submission.id, section_keys: @section_keys, explanation: @explanation }
        ).call
        unless transition.success?
          error = transition.error
          raise ActiveRecord::Rollback
        end

        submission.update!(
          status: "changes_requested", reviewed_by: @actor, reviewed_at: Time.current,
          review_explanation: @explanation
        )
        CreateDeliveries.for_owners(submission, "owner_changes_requested")
      end

      return failure(error, submission:) if error

      DispatchPendingDeliveriesJob.perform_later(submission.id)
      Result.success(submission:, section_keys: @section_keys)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence, submission:)
    end

    private

    def failure(message, submission: nil)
      Result.failure(message, submission:, section_keys: @section_keys)
    end
  end
end
