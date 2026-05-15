class PropertyPolicy < ApplicationRecord
  belongs_to :hotel

  validates :check_in_time, presence: true
  validates :check_out_time, presence: true
  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :usd_rate, presence: true

  before_validation :normalize_currency

  private

  def normalize_currency
    self.currency = CurrencyCatalog.normalize(currency)
  end
end
