class ComplaintRequest < ApplicationRecord
  belongs_to :booking

  STATUSES = %w[pending resolved failed].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :complaint_details, presence: true
  validates :requested_at, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

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

  def resolved?
    status == "resolved"
  end

  def pending?
    status == "pending"
  end

  def failed?
    status == "failed"
  end
end
