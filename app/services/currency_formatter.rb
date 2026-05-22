# frozen_string_literal: true

class CurrencyFormatter
  include ActiveSupport::NumberHelper

  def self.format(amount, currency:, symbol: true)
    new(amount, currency: currency, symbol: symbol).format
  end

  def initialize(amount, currency:, symbol: true)
    @amount = amount
    @currency = CurrencyCatalog.normalize(currency)
    @symbol = symbol
  end

  def format
    return "-" if amount.blank?

    unit = ""
    if @symbol
      symbol_str = CurrencyCatalog.symbol_for(currency)
      unit = "#{symbol_str} " if symbol_str.present?
    end

    number_to_currency(
      amount,
      unit: unit,
      precision: CurrencyCatalog.precision_for(currency),
      delimiter: ","
    )
  end

  private

  attr_reader :amount, :currency
end
