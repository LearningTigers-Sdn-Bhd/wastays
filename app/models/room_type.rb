class RoomType < ApplicationRecord
  include HotelScopable

  has_many :room_rates, dependent: :destroy
  has_many :room_inventories, dependent: :destroy
  has_many_attached :photos

  validates :name, presence: true
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_adults, presence: true, numericality: { greater_than: 0 }
  validates :base_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
