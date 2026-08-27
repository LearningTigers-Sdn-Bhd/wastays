# frozen_string_literal: true

class HousekeepingRequest < ApplicationRecord
  include RoomIdentifiable

  belongs_to :booking, optional: true
  belongs_to :room_type, optional: true
  belongs_to :hotel, optional: true

  STATUSES = %w[new assigned in_progress completed failed cancelled no_task pending].freeze

  # The three jobs this table does, which used to be told apart by reading the
  # details somebody typed.
  #
  # "guest_request" is asked for by a guest, against a stay, and is answered on
  # the Requests board. The other two are work on a room nobody is in, dispatched
  # from the housekeeping board -- which is what OPERATIONAL_CONTEXTS names.
  WORK_CONTEXTS = %w[guest_request vacant_room_task checkout_turnover].freeze
  OPERATIONAL_CONTEXTS = %w[vacant_room_task checkout_turnover].freeze

  # Statuses that take a request off the housekeeping board for good. Note
  # that "pending" is not among them: it is where a request lands before
  # anyone triages it, which is precisely when it needs to be visible.
  CLOSED_STATUSES = %w[completed failed cancelled].freeze

  enum :status, STATUSES.index_by(&:itself), scopes: false

  validates :status, presence: true
  validates :work_context, inclusion: { in: WORK_CONTEXTS }
  validates :request_details, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :search, ->(query) { HotelPortal::HousekeepingRequestsSearchQuery.new(self, query: query).call }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :open_tasks, -> { active.where.not(status: CLOSED_STATUSES) }
  scope :guest_requests, -> { where(work_context: "guest_request") }
  scope :vacant_room_tasks, -> { where(work_context: "vacant_room_task") }
  scope :checkout_turnovers, -> { where(work_context: "checkout_turnover") }
  scope :operational_tasks, -> { where(work_context: OPERATIONAL_CONTEXTS) }

  # A request belongs to a hotel by its own column when it has one, and
  # otherwise by the booking it hangs off. Written as a subquery rather than a
  # join so it composes with callers that join for their own reasons.
  scope :in_hotel, ->(hotel) { where(hotel_id: hotel.id).or(where(hotel_id: nil, booking_id: hotel.bookings.select(:id))) }

  def open_task?
    !archived? && !status.in?(CLOSED_STATUSES)
  end

  def guest_request? = work_context == "guest_request"
  def vacant_room_task? = work_context == "vacant_room_task"
  def checkout_turnover? = work_context == "checkout_turnover"
  def operational_task? = work_context.in?(OPERATIONAL_CONTEXTS)

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
