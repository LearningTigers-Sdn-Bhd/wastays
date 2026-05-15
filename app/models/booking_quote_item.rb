class BookingQuoteItem < ApplicationRecord
  belongs_to :booking_quote
  belongs_to :room_type

  delegate :hotel, to: :booking_quote

  validates :quantity, :subtotal, presence: true
end
