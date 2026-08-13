# frozen_string_literal: true

class OnboardingSubmission < ApplicationRecord
  STATUSES = %w[pending_review changes_requested approved].freeze
  SNAPSHOT_VERSION = 1

  belongs_to :hotel
  belongs_to :submitted_by, class_name: "User"
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_many :deliveries, class_name: "OnboardingDelivery", dependent: :destroy

  attr_readonly :hotel_id, :submitted_by_id, :idempotency_key, :snapshot_version,
                :snapshot, :readiness_snapshot, :configuration_digest, :submitted_at

  validates :idempotency_key, :configuration_digest, :submitted_at, presence: true
  validates :idempotency_key, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :snapshot_version, numericality: { only_integer: true, greater_than: 0 }
  validates :reviewed_by, :reviewed_at, presence: true, unless: :pending_review?
  validates :review_explanation, presence: true, if: :changes_requested?

  scope :newest_first, -> { order(submitted_at: :desc, id: :desc) }

  def pending_review? = status == "pending_review"
  def changes_requested? = status == "changes_requested"
  def approved? = status == "approved"
end
