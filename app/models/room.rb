# frozen_string_literal: true

class Room < ApplicationRecord
  include HotelScopable

  belongs_to :room_type
  belongs_to :room_group, optional: true

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  before_validation :normalize_number

  validates :number, presence: true, uniqueness: { scope: :hotel_id, case_sensitive: true }
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :room_type_belongs_to_hotel
  validate :room_group_belongs_to_hotel
  validate :number_is_immutable, on: :update
  validate :room_type_is_immutable, on: :update

  def archive!
    update!(archived_at: Time.current) if active?
    self
  end

  def restore!
    update!(archived_at: nil) if archived?
    self
  end

  def active? = archived_at.nil?
  def archived? = archived_at.present?

  private

  def normalize_number
    self.number = number.to_s.strip
  end

  def room_type_belongs_to_hotel
    return if room_type.blank? || hotel_id.blank? || room_type.hotel_id == hotel_id

    errors.add(:room_type, "must belong to the same hotel")
  end

  def room_group_belongs_to_hotel
    return if room_group.blank? || hotel_id.blank? || room_group.hotel_id == hotel_id

    errors.add(:room_group, "must belong to the same hotel")
  end

  def number_is_immutable
    errors.add(:number, "cannot be changed") if will_save_change_to_number?
  end

  def room_type_is_immutable
    errors.add(:room_type, "cannot be changed") if will_save_change_to_room_type_id?
  end
end
