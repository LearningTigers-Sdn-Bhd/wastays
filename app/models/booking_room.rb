class BookingRoom < ApplicationRecord
  belongs_to :booking
  belongs_to :room_type
  belongs_to :rate_plan, optional: true
  has_many :booking_folios, dependent: :restrict_with_error
  has_many :ota_financial_components, dependent: :restrict_with_error

  delegate :hotel, to: :booking

  validates :subtotal, presence: true
  validates :booking_id, uniqueness: true, on: :create

  def quantity
    1
  end
end
