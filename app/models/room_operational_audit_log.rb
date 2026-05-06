# frozen_string_literal: true

class RoomOperationalAuditLog < ApplicationRecord
  EVENT_TYPES = %w[room_status_changed checkout_marked_pending_cleaning assignment_override].freeze

  belongs_to :hotel
  belongs_to :room_type, optional: true
  belongs_to :booking, optional: true
  belongs_to :user, optional: true

  validates :room_number, :event_type, :metadata, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
end
