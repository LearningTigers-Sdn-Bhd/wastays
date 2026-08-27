# frozen_string_literal: true

class RoomStatus < ApplicationRecord
  include RoomIdentifiable

  STATUSES = %w[ready dirty cleaning awaiting_inspection inspection_failed out_of_service late_checkout_detected].freeze
  ASSIGNABLE_STATUSES = %w[ready].freeze

  scope :priority, -> { where(priority: true) }
  scope :dnd, -> { where(dnd: true) }

  belongs_to :hotel

  def active_dnd?
    dnd && dnd_date == hotel.current_business_date
  end
  belongs_to :room_type
  belongs_to :last_changed_by, class_name: "User", optional: true
  belongs_to :assigned_to, class_name: "User", optional: true

  validates :room_number, presence: true, uniqueness: { scope: [ :hotel_id, :room_type_id ] }
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
