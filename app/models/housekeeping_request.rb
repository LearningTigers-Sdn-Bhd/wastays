class HousekeepingRequest < ApplicationRecord
  belongs_to :booking

  STATUSES = %w[pending in_progress completed failed cancelled].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :request_details, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def display_requested_at
    requested_at || created_at
  end

  def internal_notes_list
    Array(internal_notes).compact
  end

  def add_internal_note(body, user_name: nil)
    note_body = body.to_s.strip
    return if note_body.blank?

    notes = internal_notes_list
    notes << {
      "body" => note_body,
      "created_at" => Time.current.iso8601,
      "created_by_name" => user_name
    }.compact
    self.internal_notes = notes
  end

  def completed?
    status == "completed"
  end

  def pending?
    status == "pending"
  end

  def in_progress?
    status == "in_progress"
  end

  def failed?
    status == "failed"
  end

  def cancelled?
    status == "cancelled"
  end

  def archived?
    archived_at.present?
  end

  def archive!
    self.archived_at = Time.current
  end

  def unarchive!
    self.archived_at = nil
  end
end
