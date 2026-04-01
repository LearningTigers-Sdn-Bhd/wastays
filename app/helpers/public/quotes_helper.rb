module Public::QuotesHelper
  def display_amount(amount, quote_currency:, display_currency:, hotel:)
    value = convert_amount(amount, quote_currency: quote_currency, display_currency: display_currency, hotel: hotel)
    "#{currency_label(display_currency)} #{number_with_precision(value, precision: 2)}"
  end

  def currency_label(currency)
    currency == 'USD' ? 'USD' : 'RM'
  end

  def convert_amount(amount, quote_currency:, display_currency:, hotel:)
    return amount if quote_currency == display_currency

    rate = hotel.usd_conversion_rate.to_d
    return amount / rate if quote_currency == 'MYR' && display_currency == 'USD'
    return amount * rate if quote_currency == 'USD' && display_currency == 'MYR'

    amount
  end
end
