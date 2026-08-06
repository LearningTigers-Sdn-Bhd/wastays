require 'rails_helper'

RSpec.describe CurrencyFormatter do
  it "formats two-decimal currencies with symbol by default" do
    expect(described_class.format(1234.5, currency: 'MYR')).to eq('RM 1,234.50')
  end

  it "formats zero-decimal currencies with symbol by default" do
    expect(described_class.format(1234.56, currency: 'JPY')).to eq('¥ 1,235')
  end

  it "supports suppressing symbols" do
    expect(described_class.format(1234.5, currency: 'MYR', symbol: false)).to eq('1,234.50')
    expect(described_class.format(1234.56, currency: 'JPY', symbol: false)).to eq('1,235')
  end
end
