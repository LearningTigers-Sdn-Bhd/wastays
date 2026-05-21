require 'rails_helper'

RSpec.describe CurrencyFormatter do
  it "formats two-decimal currencies" do
    expect(described_class.format(1234.5, currency: 'MYR')).to eq('1,234.50')
  end

  it "formats zero-decimal currencies" do
    expect(described_class.format(1234.56, currency: 'JPY')).to eq('1,235')
  end
end
