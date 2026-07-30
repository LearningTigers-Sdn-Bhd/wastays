# frozen_string_literal: true

class HousekeepingRequest < ApplicationRecord
  belongs_to :booking, optional: true
  belongs_to :room_type, optional: true
  belongs_to :hotel, optional: true

  STATUSES = %w[new assigned in_progress completed failed cancelled no_task pending].freeze

  # Statuses that take a request off the housekeeping board for good. Note
  # that "pending" is not among them: it is where a request lands before
  # anyone triages it, which is precisely when it needs to be visible.
  CLOSED_STATUSES = %w[completed failed cancelled].freeze

  enum :status, STATUSES.index_by(&:itself), scopes: false

  validates :status, presence: true
  validates :request_details, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :search, ->(query) { HotelPortal::HousekeepingRequestsSearchQuery.new(self, query: query).call }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :open_tasks, -> { active.where.not(status: CLOSED_STATUSES) }

  def open_task?
    !archived? && !status.in?(CLOSED_STATUSES)
  end

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
