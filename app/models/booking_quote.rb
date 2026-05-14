class BookingQuote < ApplicationRecord
  belongs_to :hotel
  has_many :booking_quote_items, dependent: :destroy

  validates :check_in, :check_out, :adults, :total_amount, :expires_at, :token, presence: true
  validates :token, uniqueness: true
  validates :currency, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :display_currency, inclusion: { in: ->(_) { CurrencyCatalog.codes }, allow_blank: true }

  before_validation :generate_token, on: :create
  before_validation :normalize_currencies

  private

  def normalize_currencies
    self.currency = CurrencyCatalog.normalize(currency)
    self.display_currency = CurrencyCatalog.normalize(display_currency, fallback: nil) if display_currency.present?
  end

  def generate_token
    self.token ||= SecureRandom.hex(16)
  end
end
