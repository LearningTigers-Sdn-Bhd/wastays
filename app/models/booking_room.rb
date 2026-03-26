class BookingRoom < ApplicationRecord
  belongs_to :booking
  belongs_to :room_type

  validates :quantity, :subtotal, presence: true
end
