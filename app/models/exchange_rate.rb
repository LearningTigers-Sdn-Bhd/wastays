# frozen_string_literal: true

class ExchangeRate < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  before_validation :normalize_currency_codes

  validates :base_currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :currency_code, presence: true, uniqueness: { scope: :base_currency, case_sensitive: false }
  validates :currency_code, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :rate, presence: true, numericality: { greater_than: 0 }
  validates :effective_at, presence: true
  validates :source, presence: true
  validate :rate_is_one_for_same_currency

  scope :active, -> { where(active: true) }

  def self.rate_for(from, to)
    return 1.to_d if from == to

    # Try direct rate first
    direct_rate = active.find_by(base_currency: from, currency_code: to)
    return direct_rate.rate if direct_rate

    # Try inverse rate
    inverse_rate = active.find_by(base_currency: to, currency_code: from)
    return 1.to_d / inverse_rate.rate if inverse_rate

    nil
  end

  private

  def normalize_currency_codes
    self.base_currency = base_currency.to_s.upcase.strip
    self.currency_code = currency_code.to_s.upcase.strip
  end

  def rate_is_one_for_same_currency
    return unless base_currency == currency_code && rate.present? && rate.to_d != 1.to_d

    errors.add(:rate, "must be 1.0 when base currency and target currency are the same")
  end
end
