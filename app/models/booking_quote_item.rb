class BookingQuoteItem < ApplicationRecord
  belongs_to :booking_quote
  belongs_to :room_type

  validates :quantity, :subtotal, presence: true
end
