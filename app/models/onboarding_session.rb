class OnboardingSession < ApplicationRecord
  belongs_to :hotel
  belongs_to :trainer, class_name: "User"

  validates :status, presence: true, inclusion: { in: %w[scheduled completed cancelled] }
  validates :scheduled_at, presence: true

  scope :upcoming, -> { where(status: "scheduled").where("scheduled_at >= ?", Time.current) }
  scope :completed, -> { where(status: "completed") }

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end
end
