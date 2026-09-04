require 'rails_helper'

RSpec.describe CurrencyFormatter do
  it "labels money with the ISO code by default" do
    expect(described_class.format(1234.5, currency: 'MYR')).to eq('MYR 1,234.50')
    expect(described_class.format(1234.5, currency: 'SGD')).to eq('SGD 1,234.50')
  end

  it "drops the decimals on a zero-decimal currency" do
    expect(described_class.format(1234.56, currency: 'JPY')).to eq('JPY 1,235')
  end

  it "keeps the minus with the number so a credit reads the same everywhere" do
    expect(described_class.format(-5, currency: 'MYR')).to eq('MYR -5.00')
  end

  it "supports the symbol for a surface that has already stated its currency" do
    expect(described_class.format(1234.5, currency: 'MYR', unit: :symbol)).to eq('RM 1,234.50')
    expect(described_class.format(1234.56, currency: 'JPY', unit: :symbol)).to eq('¥ 1,235')
  end

  it "supports a bare number" do
    expect(described_class.format(1234.5, currency: 'MYR', unit: :none)).to eq('1,234.50')
  end

  it "returns a dash for a blank amount" do
    expect(described_class.format(nil, currency: 'MYR')).to eq('-')
  end
end
