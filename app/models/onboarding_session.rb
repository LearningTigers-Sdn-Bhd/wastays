class OnboardingSession < ApplicationRecord
  belongs_to :hotel

  validates :status, presence: true, inclusion: { in: %w[scheduled completed cancelled] }
  validates :scheduled_at, presence: true
  validates :trainer_name, presence: true
  validates :meeting_link, format: { with: /\Ahttps?:\/\/.+\z/i, allow_blank: true }

  before_validation :normalize_meeting_link

  scope :upcoming, -> { where(status: "scheduled").where("scheduled_at >= ?", Time.current) }
  scope :completed, -> { where(status: "completed") }

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end

  def formatted_meeting_link
    meeting_link
  end

  private

  def normalize_meeting_link
    return if meeting_link.blank?
    return if meeting_link.match?(/\Ahttps?:\/\//i)

    self.meeting_link = "https://#{meeting_link}" if meeting_link.include?(".")
  end
end
