class CheckOutRequest < ApplicationRecord
  belongs_to :booking
  belongs_to :acknowledged_by_user, class_name: "User", optional: true

  # Keep legacy values valid while new workflow updates use housekeeping statuses.
  STATUSES = %w[new assigned in_progress completed no_task cancelled pending acknowledged].freeze

  # A request still owed work, which is every status that is not an ending.
  # Spelled out rather than subtracted so a new status has to be placed here
  # deliberately, and named to match HousekeepingRequest.open_tasks -- the two
  # sit side by side on the housekeeping board.
  OPEN_STATUSES = %w[new assigned in_progress pending acknowledged].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :requested_at, presence: true

  scope :open_tasks, -> { where(status: OPEN_STATUSES) }
  scope :recent_first, -> { order(created_at: :desc) }

  def open_task?
    status.in?(OPEN_STATUSES)
  end

  def pending?
    status.in?(%w[new pending])
  end

  def acknowledged?
    status.in?(%w[assigned in_progress acknowledged])
  end
end
