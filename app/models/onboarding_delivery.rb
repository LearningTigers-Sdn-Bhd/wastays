# frozen_string_literal: true

class OnboardingDelivery < ApplicationRecord
  DELIVERY_TYPES = %w[
    staff_invitation corporate_invitation admin_submitted
    owner_changes_requested owner_approved
  ].freeze
  STATUSES = %w[pending processing sent held failed].freeze

  belongs_to :onboarding_submission

  validates :delivery_type, inclusion: { in: DELIVERY_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, presence: true, uniqueness: true

  scope :retryable, -> { where(status: %w[pending failed]) }
  scope :unfinished, -> { where(status: %w[pending processing failed]) }

  def complete!(held: false)
    update!(status: held ? "held" : "sent", completed_at: Time.current, error_message: nil)
  end

  def fail!(error)
    update!(status: "failed", error_message: error.to_s.truncate(1_000), attempted_at: Time.current)
  end
end
