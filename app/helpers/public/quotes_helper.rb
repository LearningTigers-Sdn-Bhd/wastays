module Public::QuotesHelper
  def converted_amount(amount, from:, to:)
    CurrencyConverter.convert(amount, from: from, to: to)&.amount || amount
  end

  def quote_time_remaining(expires_at)
    minutes = ((expires_at - Time.current) / 60).to_i
    "#{minutes}m"
  end
end
