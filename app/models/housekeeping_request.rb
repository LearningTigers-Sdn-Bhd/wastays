class HousekeepingRequest < ApplicationRecord
  belongs_to :booking, optional: true
  belongs_to :room_type, optional: true
  belongs_to :hotel, optional: true

  STATUSES = %w[new assigned in_progress completed failed cancelled no_task pending].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :request_details, presence: true

  scope :recent_first, -> { order(created_at: :desc) }

  scope :search, ->(query) {
    return all if query.blank?
    q = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.downcase)}%"
    joins(:booking)
      .left_joins(booking: :booking_rooms)
      .where(
        "housekeeping_requests.external_id ILIKE :q OR " \
        "housekeeping_requests.request_details ILIKE :q OR " \
        "bookings.confirmation_token ILIKE :q OR " \
        "bookings.guest_name ILIKE :q OR " \
        "bookings.guest_email ILIKE :q OR " \
        "bookings.guest_phone ILIKE :q OR " \
        "housekeeping_requests.room_number ILIKE :q OR " \
        "booking_rooms.room_number ILIKE :q",
        q: q
      ).distinct
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
