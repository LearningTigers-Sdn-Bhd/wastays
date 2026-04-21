class OnboardingSession < ApplicationRecord
  belongs_to :hotel

  validates :status, presence: true, inclusion: { in: %w[scheduled completed cancelled] }
  validates :scheduled_at, presence: true
  validates :trainer_name, presence: true

  scope :upcoming, -> { where(status: "scheduled").where("scheduled_at >= ?", Time.current) }
  scope :completed, -> { where(status: "completed") }

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end

  def formatted_meeting_link
    return nil if meeting_link.blank?
    meeting_link.match?(/\Ahttps?:\/\//) ? meeting_link : "https://#{meeting_link}"
  end
end
