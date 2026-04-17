class ComplaintRequest < ApplicationRecord
  belongs_to :booking

  STATUSES = %w[pending in_progress resolved failed cancelled].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :complaint_details, presence: true
  validates :requested_at, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  scope :search, ->(query) {
    return all if query.blank?
    q = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.downcase)}%"
    joins(:booking).where(
      "complaint_requests.external_id ILIKE :q OR complaint_requests.complaint_details ILIKE :q OR bookings.confirmation_token ILIKE :q OR bookings.guest_name ILIKE :q OR bookings.guest_email ILIKE :q OR bookings.guest_phone ILIKE :q",
      q: q
    )
  }

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

  def resolved?
    status == "resolved"
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

  def resolved!
    self.status = "resolved"
    self.completed_at ||= Time.current
  end

  def reopen!
    self.status = "in_progress"
    self.completed_at = nil
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
