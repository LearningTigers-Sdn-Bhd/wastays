class BookingRoom < ApplicationRecord
  belongs_to :booking
  belongs_to :room_type
  belongs_to :rate_plan, optional: true
  has_many :booking_folios, dependent: :restrict_with_error

  delegate :hotel, to: :booking

  validates :quantity, :subtotal, presence: true
  validates :quantity, numericality: { only_integer: true, equal_to: 1 }, if: :enforce_single_room_stay?
  validate :one_operational_room_per_booking, if: :enforce_single_room_stay?

  private

  def enforce_single_room_stay?
    BookingRedesign.enabled? && (new_record? || will_save_change_to_quantity?)
  end

  def one_operational_room_per_booking
    return if booking.blank?
    return unless booking.booking_rooms.where.not(id: id).exists?

    errors.add(:booking, "can only have one operational room stay")
  end
end
