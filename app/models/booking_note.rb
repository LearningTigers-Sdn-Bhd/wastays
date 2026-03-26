class BookingNote < ApplicationRecord
  belongs_to :booking
  belongs_to :user

  validates :body, presence: true
end
