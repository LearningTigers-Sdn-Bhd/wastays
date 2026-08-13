# frozen_string_literal: true

module Onboarding
  class DispatchPendingDeliveriesJob < ApplicationJob
    queue_as :default

    def perform(submission_id = nil)
      stale = OnboardingDelivery.where(status: "processing").where(updated_at: ...15.minutes.ago)
      stale = stale.where(onboarding_submission_id: submission_id) if submission_id
      stale.update_all(status: "failed", error_message: "Delivery worker stopped before completion", updated_at: Time.current)

      scope = OnboardingDelivery.retryable.order(:id)
      scope = scope.where(onboarding_submission_id: submission_id) if submission_id
      scope.find_each { |delivery| DeliverJob.perform_later(delivery.id) }
    end
  end
end
