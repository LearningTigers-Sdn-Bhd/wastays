class BookingGuest < ApplicationRecord
  belongs_to :booking
  belongs_to :guest

  validates :is_primary, inclusion: { in: [ true, false ] }
end
