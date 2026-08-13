class RoomTypeRatePlanOccupancyPrice < ApplicationRecord
  belongs_to :room_type_rate_plan

  validates :adults, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :adults, uniqueness: { scope: :room_type_rate_plan_id }
  validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :adults_within_room_capacity

  private

  def adults_within_room_capacity
    return if adults.blank? || room_type_rate_plan.blank?
    return if adults <= room_type_rate_plan.room_type.max_adults.to_i

    errors.add(:adults, "cannot exceed the room category's maximum adults")
  end
end
