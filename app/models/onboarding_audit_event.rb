# frozen_string_literal: true

class OnboardingAuditEvent < ApplicationRecord
  EVENT_TYPES = %w[
    initialized started completed skipped invalidated submitted changes_requested approved
    training_keep_selected training_reset_requested training_reset_retried
    training_reset_failed training_reset_completed launched suspended reactivated
  ].freeze

  belongs_to :hotel
  belongs_to :user, optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :section_key, inclusion: { in: Onboarding::SectionCatalog.keys }, allow_nil: true
  validates :occurred_at, presence: true
end
