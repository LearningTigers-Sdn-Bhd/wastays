require 'rails_helper'

RSpec.describe CurrencyConverter do
  let!(:usd_myr) { create(:exchange_rate, base_currency: 'USD', currency_code: 'MYR', rate: 4.0) }
  let!(:eur_myr) { create(:exchange_rate, base_currency: 'EUR', currency_code: 'MYR', rate: 5.0) }

  it 'converts through property base currency (triangulation)' do
    hotel = create(:hotel, default_currency: 'USD')
    # 1 USD = 4 MYR, 1 USD = 0.8 EUR (inverse of 1 EUR = 1.25 USD)
    create(:exchange_rate, base_currency: 'USD', currency_code: 'EUR', rate: 0.8)
    
    conversion = CurrencyConverter.convert(100, from: 'MYR', to: 'EUR', hotel: hotel)
    
    # 100 MYR -> 25 USD -> 20 EUR
    expect(conversion.amount).to eq(20.0)
    expect(conversion.rate).to eq(0.2)
  end

  it 'converts MYR to USD using inverse of USD->MYR' do
    conversion = CurrencyConverter.convert(100, from: 'MYR', to: 'USD')
    expect(conversion.amount).to eq(25.0)
  end

  it 'converts USD to MYR directly' do
    conversion = CurrencyConverter.convert(100, from: 'USD', to: 'MYR')
    expect(conversion.amount).to eq(400.0)
  end

  it 'converts through MYR for non-MYR pairs (legacy fallback)' do
    # 1 USD = 4 MYR, 1 EUR = 5 MYR => 1 USD = 0.8 EUR
    conversion = CurrencyConverter.convert(100, from: 'USD', to: 'EUR')
    expect(conversion.amount).to eq(80.0)
  end

  it 'returns nil when a rate is missing or inactive' do
    usd_myr.update(active: false)
    expect(CurrencyConverter.convert(100, from: 'USD', to: 'MYR')).to be_nil
  end
end
