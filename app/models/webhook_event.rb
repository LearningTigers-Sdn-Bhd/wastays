class WebhookEvent < ApplicationRecord
  validates :gateway, presence: true
  validates :external_id, presence: true, uniqueness: { scope: :gateway }
  validates :status, presence: true

  STATUSES = %w[pending processed failed].freeze

  scope :failed, -> { where(status: "failed") }
  scope :pending, -> { where(status: "pending") }
end
