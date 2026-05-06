# frozen_string_literal: true

class RoomStatus < ApplicationRecord
  STATUSES = %w[ready pending_cleaning preparing inspection_failed out_of_service].freeze
  ASSIGNABLE_STATUSES = %w[ready].freeze

  belongs_to :hotel
  belongs_to :room_type
  belongs_to :last_changed_by, class_name: "User", optional: true

  validates :room_number, presence: true, uniqueness: { scope: :hotel_id }
  validates :status, presence: true, inclusion: { in: STATUSES }

  before_validation :normalize_room_number

  def assignable?
    ASSIGNABLE_STATUSES.include?(status)
  end

  private

  def normalize_room_number
    self.room_number = room_number.to_s.strip if room_number.present?
  end
end
