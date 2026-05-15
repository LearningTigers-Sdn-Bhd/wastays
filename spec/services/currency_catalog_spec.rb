require 'rails_helper'

RSpec.describe CurrencyCatalog do
  it 'returns ISO metadata for common test currencies' do
    expect(described_class.find('MYR').symbol).to eq('RM')
    expect(described_class.find('USD').label).to include('US Dollar')
    expect(described_class.find('JPY').precision).to eq(0)
    expect(described_class.find('GBP').symbol).to eq('£')
  end

  it 'normalizes and validates ISO currency codes' do
    expect(described_class.normalize(' usd ')).to eq('USD')
    expect(described_class.valid?('JPY')).to be(true)
    expect(described_class.valid?('ZZZ')).to be(false)
  end
end
