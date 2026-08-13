# frozen_string_literal: true

module Onboarding
  class DeliverJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(delivery_id)
      delivery = OnboardingDelivery.find(delivery_id)
      should_process = false
      delivery.with_lock do
        return unless delivery.status.in?(%w[pending failed])

        delivery.update!(
          status: "processing", attempt_count: delivery.attempt_count + 1,
          attempted_at: Time.current, error_message: nil
        )
        should_process = true
      end
      return unless should_process

      process(delivery)
    rescue StandardError => e
      delivery&.fail!(e.message)
      raise
    end

    private

    def process(delivery)
      case delivery.delivery_type
      when "staff_invitation", "corporate_invitation"
        process_invitation(delivery)
      when "admin_submitted"
        OnboardingMailer.submitted(delivery).deliver_now
        delivery.complete!
      when "owner_changes_requested"
        OnboardingMailer.changes_requested(delivery).deliver_now
        delivery.complete!
      when "owner_approved"
        OnboardingMailer.approved(delivery).deliver_now
        delivery.complete!
      else
        raise ArgumentError, "Unsupported onboarding delivery: #{delivery.delivery_type}"
      end
    end

    def process_invitation(delivery)
      draft = delivery.source_type.constantize.find(delivery.source_id)
      result = DeliverInvitationDraft.call(draft:, actor: delivery.onboarding_submission.submitted_by)
      raise result.error unless result.success?

      delivery.complete!(held: result.held)
    end
  end
end
