class BookingRoom < ApplicationRecord
  belongs_to :booking
  belongs_to :room_type
  belongs_to :rate_plan, optional: true

  delegate :hotel, to: :booking

  validates :quantity, :subtotal, presence: true
end
