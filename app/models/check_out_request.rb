class CheckOutRequest < ApplicationRecord
  belongs_to :booking
  belongs_to :acknowledged_by_user, class_name: "User", optional: true

  STATUSES = %w[pending acknowledged completed cancelled].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :requested_at, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :recent_first, -> { order(created_at: :desc) }

  def pending?
    status == "pending"
  end

  def acknowledged?
    status == "acknowledged"
  end
end
