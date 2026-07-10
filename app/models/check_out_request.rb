class CheckOutRequest < ApplicationRecord
  belongs_to :booking
  belongs_to :acknowledged_by_user, class_name: "User", optional: true

  # Keep legacy values valid while new workflow updates use housekeeping statuses.
  STATUSES = %w[new assigned in_progress completed no_task cancelled pending acknowledged].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :requested_at, presence: true

  scope :pending, -> { where(status: %w[new assigned in_progress pending acknowledged]) }
  scope :recent_first, -> { order(created_at: :desc) }

  def pending?
    status.in?(%w[new pending])
  end

  def acknowledged?
    status.in?(%w[assigned in_progress acknowledged])
  end
end
