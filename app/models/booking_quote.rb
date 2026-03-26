class BookingQuote < ApplicationRecord
  belongs_to :hotel
  has_many :booking_quote_items, dependent: :destroy

  validates :check_in, :check_out, :adults, :total_amount, :expires_at, :token, presence: true
  validates :token, uniqueness: true

  before_validation :generate_token, on: :create

  private

  def generate_token
    self.token ||= SecureRandom.hex(16)
  end
end
