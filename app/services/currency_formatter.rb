# frozen_string_literal: true

class CurrencyFormatter
  include ActiveSupport::NumberHelper

  def self.format(amount, currency:)
    new(amount, currency: currency).format
  end

  def initialize(amount, currency:)
    @amount = amount
    @currency = CurrencyCatalog.normalize(currency)
  end

  def format
    return "-" if amount.blank?

    number_to_currency(
      amount,
      unit: "",
      precision: CurrencyCatalog.precision_for(currency),
      delimiter: ","
    )
  end

  private

  attr_reader :amount, :currency
end
