# frozen_string_literal: true

module Onboarding
  # An owner deciding this property bills no companies directly.
  #
  # Unlike the charge sections, this one discards its records: corporate drafts
  # are onboarding-only rows whose whole purpose is to be delivered later, so
  # leaving them queued behind a skip would send invitations the owner just said
  # they did not want. Drafts already delivered are kept — they are the marker
  # that stops submission sending twice.
  class DecideNoCorporateAccounts
    Result = ApplicationResult.define(:section)

    def self.call(...) = new(...).call

    def initialize(hotel:, actor:)
      @hotel = hotel
      @actor = actor
    end

    def call
      transition_result = nil
      OnboardingCorporateDraft.transaction do
        @hotel.onboarding_corporate_drafts.undelivered.destroy_all
        transition_result = UpdateSection.new(
          hotel: @hotel,
          section_key: "corporate_accounts",
          state: "skipped",
          actor: @actor,
          metadata: {
            source: "corporate_account_setup",
            decision: "no_corporate_accounts",
            draft_count: @hotel.onboarding_corporate_drafts.reload.size
          }
        ).call
        raise ActiveRecord::Rollback unless transition_result.success?
      end
      return Result.failure(transition_result.error, section: transition_result.section) unless transition_result.success?

      Result.success(section: transition_result.section)
    end
  end
end
