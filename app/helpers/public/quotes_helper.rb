module Public::QuotesHelper
  def display_amount(amount, quote_currency:, display_currency:, hotel:)
    conversion = CurrencyConverter.convert(amount, from: quote_currency, to: display_currency)
    target_currency = conversion.present? ? display_currency : quote_currency
    value = conversion&.amount || amount

    CurrencyFormatter.format(value, currency: target_currency)
  end

  def converted_amount(amount, from:, to:)
    CurrencyConverter.convert(amount, from: from, to: to)&.amount || amount
  end

  def quote_time_remaining(expires_at)
    minutes = ((expires_at - Time.current) / 60).to_i
    "#{minutes}m"
  end
end
