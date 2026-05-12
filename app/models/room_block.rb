# frozen_string_literal: true

class RoomBlock < ApplicationRecord
  BLOCK_TYPES = %w[maintenance deep_cleaning renovation owner_use admin_hold].freeze

  belongs_to :hotel
  belongs_to :room_type
  belongs_to :user, optional: true

  validates :room_number, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :block_type, presence: true
  validates :reason, presence: true

  validate :end_date_after_start_date
  validate :no_overlapping_blocks

  scope :active_on, ->(date) { where("start_date <= ? AND end_date >= ?", date, date) }
  scope :for_date_range, ->(start_date, end_date) { where("start_date <= ? AND end_date >= ?", end_date, start_date) }

  def active_on?(date)
    return false if start_date.blank? || end_date.blank?

    (start_date..end_date).include?(date)
  end

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?

    if end_date < start_date
      errors.add(:end_date, "must be after the start date")
    end
  end

  def no_overlapping_blocks
    return if start_date.blank? || end_date.blank? || room_number.blank?

    overlapping = RoomBlock.where(hotel_id: hotel_id, room_type_id: room_type_id, room_number: room_number)
                          .where.not(id: id)
                          .where("start_date <= ? AND end_date >= ?", end_date, start_date)

    if overlapping.any?
      errors.add(:base, "This room is already blocked during this period")
    end
  end
end
