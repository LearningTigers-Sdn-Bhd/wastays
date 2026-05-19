# frozen_string_literal: true

class CurrencyConverter
  Conversion = Struct.new(:amount, :rate, :source, keyword_init: true)

  def self.convert(amount, from:, to:, hotel: nil)
    new(hotel: hotel).convert(amount, from: from, to: to)
  end

  def initialize(hotel: nil)
    @hotel = hotel
  end

  def convert(amount, from:, to:)
    source_currency = CurrencyCatalog.normalize(from)
    target_currency = CurrencyCatalog.normalize(to)
    numeric_amount = amount.to_d

    return Conversion.new(amount: numeric_amount, rate: 1.to_d, source: "same_currency") if source_currency == target_currency

    # 1. Try direct or inverse rate from global table
    rate = ExchangeRate.rate_for(source_currency, target_currency)

    # 2. If not found, try triangulation through MYR (legacy/fallback)
    if rate.nil?
      source_to_myr = ExchangeRate.rate_for(source_currency, "MYR")
      target_to_myr = ExchangeRate.rate_for(target_currency, "MYR")

      if source_to_myr && target_to_myr
        rate = source_to_myr / target_to_myr
      end
    end

    # 3. If still not found, try triangulation through Property Base Currency
    if rate.nil? && @hotel&.default_currency.present?
      base = @hotel.default_currency
      source_to_base = ExchangeRate.rate_for(base, source_currency) # Often 1 Base = X Source
      target_to_base = ExchangeRate.rate_for(base, target_currency)

      if source_to_base && target_to_base
        # If 1 Base = S source and 1 Base = T target
        # Then S source = T target => 1 source = T/S target
        rate = target_to_base / source_to_base
      end
    end

    return nil if rate.nil?

    Conversion.new(
      amount: numeric_amount * rate,
      rate: rate,
      source: "managed_fx"
    )
  end
end
