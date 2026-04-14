class HousekeepingRequest < ApplicationRecord
  belongs_to :booking

  STATUSES = %w[pending in_progress completed failed].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :request_details, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  def display_requested_at
    requested_at || created_at
  end
end
