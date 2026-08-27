# frozen_string_literal: true

class RoomOperationalAuditLog < ApplicationRecord
  include RoomIdentifiable

  EVENT_TYPES = %w[
    room_status_changed
    checkout_marked_dirty
    void_booking_marked_dirty
    assignment_override
    room_blocked_auto_status
    room_block_removed_auto_status
    no_show_released_after_night_audit
    no_show_released
    no_show_detection_cancelled
    housekeeping_request_dispatched
    housekeeping_assignment_changed
    housekeeping_room_assignment_changed
    housekeeping_room_remarks_changed
    checkout_room_cleaning_started
    checkout_room_cleaning_completed
  ].freeze

  belongs_to :hotel
  belongs_to :room_type, optional: true
  belongs_to :booking, optional: true
  belongs_to :user, optional: true

  validates :room_number, :event_type, :metadata, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
end
