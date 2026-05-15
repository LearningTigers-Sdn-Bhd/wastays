require 'rails_helper'

RSpec.describe ExchangeRate, type: :model do
  it 'normalizes and validates ISO currency codes' do
    rate = build(:exchange_rate, base_currency: ' myr ', currency_code: ' usd ')

    expect(rate).to be_valid
    expect(rate.base_currency).to eq('MYR')
    expect(rate.currency_code).to eq('USD')
  end

  it 'validates uniqueness of currency_code scoped to base_currency' do
    create(:exchange_rate, base_currency: 'MYR', currency_code: 'USD')
    duplicate = build(:exchange_rate, base_currency: 'MYR', currency_code: 'USD')

    expect(duplicate).not_to be_valid
  end

  it 'keeps rate at 1.0 when base and target are the same' do
    rate = build(:exchange_rate, base_currency: 'USD', currency_code: 'USD', rate: 1.2)

    expect(rate).not_to be_valid
    expect(rate.errors[:rate]).to include('must be 1.0 when base currency and target currency are the same')
  end

  describe '.rate_for' do
    before do
      create(:exchange_rate, base_currency: 'USD', currency_code: 'MYR', rate: 4.75)
    end

    it 'returns 1.0 for the same currency' do
      expect(ExchangeRate.rate_for('USD', 'USD')).to eq(1.0)
    end

    it 'returns the direct rate' do
      expect(ExchangeRate.rate_for('USD', 'MYR')).to eq(4.75)
    end

    it 'returns the inverse rate' do
      expect(ExchangeRate.rate_for('MYR', 'USD')).to eq(1.to_d / 4.75.to_d)
    end

    it 'returns nil if no rate found' do
      expect(ExchangeRate.rate_for('USD', 'EUR')).to be_nil
    end
  end
end
