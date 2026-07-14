# frozen_string_literal: true

class RoomOperationalAuditLog < ApplicationRecord
  EVENT_TYPES = %w[
    room_status_changed
    checkout_marked_dirty
    assignment_override
    room_blocked_auto_status
    room_block_removed_auto_status
    no_show_released_after_night_audit
    no_show_released
    review_no_show_cancelled
    housekeeping_request_dispatched
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
