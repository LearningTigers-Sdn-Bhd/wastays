# frozen_string_literal: true

class OtaRateVariancePolicy < ApplicationRecord
  MODES = %w[recommended strict custom].freeze
  RECOMMENDED_MAX_PERCENTAGE = 1.to_d
  RECOMMENDED_MAX_AMOUNT_PER_ROOM_NIGHT = 10.to_d

  belongs_to :hotel

  before_validation :apply_recommended_defaults
  before_validation :normalize_currency

  validates :hotel_id, uniqueness: true
  validates :mode, inclusion: { in: MODES }
  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :maximum_percentage, :maximum_amount_per_room_night,
    presence: true, numericality: { greater_than_or_equal_to: 0 }

  private

  def apply_recommended_defaults
    if mode == "recommended"
      self.maximum_percentage = RECOMMENDED_MAX_PERCENTAGE
      self.maximum_amount_per_room_night = RECOMMENDED_MAX_AMOUNT_PER_ROOM_NIGHT
    elsif mode == "strict"
      self.maximum_percentage ||= RECOMMENDED_MAX_PERCENTAGE
      self.maximum_amount_per_room_night ||= RECOMMENDED_MAX_AMOUNT_PER_ROOM_NIGHT
    end
  end

  def normalize_currency
    self.currency = CurrencyCatalog.normalize(currency.presence || hotel&.default_currency, fallback: nil)
  end
end
