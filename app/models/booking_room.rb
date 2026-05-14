class BookingRoom < ApplicationRecord
  belongs_to :booking
  belongs_to :room_type

  delegate :hotel, to: :booking

  validates :quantity, :subtotal, presence: true
end
