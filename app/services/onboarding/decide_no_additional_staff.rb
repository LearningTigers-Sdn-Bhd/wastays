# frozen_string_literal: true

module Onboarding
  class DecideNoAdditionalStaff
    Result = ApplicationResult.define(:section)

    def initialize(hotel:, actor:)
      @hotel = hotel
      @actor = actor
    end

    def call
      transition_result = nil
      OnboardingStaffDraft.transaction do
        @hotel.onboarding_staff_drafts.delete_all
        transition_result = UpdateSection.new(
          hotel: @hotel,
          section_key: "staff_setup",
          state: "skipped",
          actor: @actor,
          metadata: { source: "staff_draft_setup", decision: "no_additional_staff", staff_count: 0 }
        ).call
        raise ActiveRecord::Rollback unless transition_result.success?
      end
      return Result.failure(transition_result.error, section: transition_result.section) unless transition_result.success?

      Result.success(section: transition_result.section)
    end
  end
end
