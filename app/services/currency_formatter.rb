# frozen_string_literal: true

# One place that turns an amount into money for display.
#
# Two units, for two audiences:
#
# - `:symbol` (the default) suits a guest-facing page that has already stated
#   which currency it is quoting: a booking page, a quote, a rate cell.
# - `:code` suits the portal ledger, where a row can carry a different currency
#   from the row above it. `$` is shared by six currencies this system sells in,
#   and CurrencyCatalog maps both JPY and CNY to `¥`, so a symbol there would
#   let two different amounts read the same.
class CurrencyFormatter
  include ActiveSupport::NumberHelper

  UNITS = %i[symbol code none].freeze

  def self.format(amount, currency:, unit: :symbol)
    new(amount, currency: currency, unit: unit).format
  end

  def initialize(amount, currency:, unit: :symbol)
    @amount = amount
    @currency = CurrencyCatalog.normalize(currency)
    @unit = UNITS.include?(unit.to_s.to_sym) ? unit.to_s.to_sym : :symbol
  end

  def format
    return "-" if amount.blank?

    number_to_currency(amount, **number_options)
  end

  private

  attr_reader :amount, :currency

  def number_options
    options = {
      unit: unit_prefix,
      precision: CurrencyCatalog.precision_for(currency),
      delimiter: ","
    }

    # The ledger pages built this string by hand and read a credit as
    # "MYR -5.00". Keep the minus with the number rather than in front of the
    # code. The symbol unit keeps the default, which is what its callers show
    # today.
    options[:negative_format] = "%u-%n" if @unit == :code
    options
  end

  def unit_prefix
    case @unit
    when :none then ""
    when :code then currency.present? ? "#{currency} " : ""
    else
      symbol = CurrencyCatalog.symbol_for(currency)
      symbol.present? ? "#{symbol} " : ""
    end
  end
end
