require 'rails_helper'

RSpec.describe CurrencyFormatter do
  it "uses the symbol by default, so every caller that never asked reads as it did" do
    expect(described_class.format(1234.5, currency: 'MYR')).to eq('RM 1,234.50')
    expect(described_class.format(nil, currency: 'MYR')).to eq('-')
  end

  it "labels money with the ISO code on request" do
    expect(described_class.format(1234.5, currency: 'MYR', unit: :code)).to eq('MYR 1,234.50')
    # A portal row can carry a different currency from the row above it, and
    # CurrencyCatalog maps both JPY and CNY to the same symbol.
    expect(described_class.format(1234.5, currency: 'SGD', unit: :code)).to eq('SGD 1,234.50')
  end

  it "drops the decimals on a zero-decimal currency, whichever unit is asked for" do
    expect(described_class.format(1234.56, currency: 'JPY', unit: :code)).to eq('JPY 1,235')
    expect(described_class.format(1234.56, currency: 'JPY', unit: :symbol)).to eq('¥ 1,235')
  end

  it "keeps the minus with the number on the code path, so a credit reads like the folio" do
    expect(described_class.format(-5, currency: 'MYR', unit: :code)).to eq('MYR -5.00')
  end

  it "returns a bare number when the caller labels the currency itself" do
    expect(described_class.format(1234.5, currency: 'MYR', unit: :none)).to eq('1,234.50')
  end

  it "falls back to the symbol when handed a unit it does not know" do
    expect(described_class.format(1234.5, currency: 'MYR', unit: :nonsense)).to eq('RM 1,234.50')
  end
end
