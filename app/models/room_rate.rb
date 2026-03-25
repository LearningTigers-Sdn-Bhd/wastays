class RoomRate < ApplicationRecord
  belongs_to :room_type

  validates :date, presence: true
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true
  validates :date, uniqueness: { scope: :room_type_id }
end
