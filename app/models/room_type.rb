# frozen_string_literal: true

class RoomType < ApplicationRecord
  include HotelScopable

  has_many :room_rates, dependent: :destroy
  has_many :room_inventories, dependent: :destroy
  has_many :rate_plans, dependent: :destroy
  has_one :channel_mapping, as: :mappable, dependent: :destroy
  has_many_attached :photos

  before_validation :set_default_room_number_mode, on: :create

  validates :name, presence: true
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_adults, presence: true, numericality: { greater_than: 0 }
  validates :base_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :room_number_mode, presence: true, inclusion: { in: %w[range custom] }

  def room_numbers
    Array(super).flatten.compact.map(&:to_s).reject(&:blank?)
  end

  private

  def set_default_room_number_mode
    self.room_number_mode ||= "range"
  end
end
