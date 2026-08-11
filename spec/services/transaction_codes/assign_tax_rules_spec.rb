# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionCodes::AssignTaxRules do
  let(:hotel) { create(:hotel) }
  let(:room_revenue_code) { TransactionCodes::Resolver.for(hotel).room_revenue }
  let(:hotel_tax) { create(:hotel_tax, hotel: hotel) }

  it "replaces the existing rules with the given keys" do
    described_class.call(transaction_code: room_revenue_code, keys: [ "primary:sst_tax" ])
    described_class.call(transaction_code: room_revenue_code, keys: [ "primary:tourism_tax", "hotel_tax:#{hotel_tax.id}" ])

    expect(room_revenue_code.transaction_code_taxes.map(&:tax_rule_key))
      .to contain_exactly("primary:tourism_tax", "hotel_tax:#{hotel_tax.id}")
  end

  it "clears every rule when given nothing" do
    described_class.call(transaction_code: room_revenue_code, keys: [ "primary:sst_tax" ])

    described_class.call(transaction_code: room_revenue_code, keys: [])

    expect(room_revenue_code.transaction_code_taxes).to be_empty
  end

  it "ignores blanks and duplicates" do
    described_class.call(transaction_code: room_revenue_code, keys: [ "primary:sst_tax", "", "primary:sst_tax" ])

    expect(room_revenue_code.transaction_code_taxes.count).to eq(1)
  end

  it "refuses another hotel's tax without touching the existing rules" do
    described_class.call(transaction_code: room_revenue_code, keys: [ "primary:sst_tax" ])
    foreign_tax = create(:hotel_tax, hotel: create(:hotel))

    expect {
      described_class.call(transaction_code: room_revenue_code, keys: [ "hotel_tax:#{foreign_tax.id}" ])
    }.to raise_error(ArgumentError, /unavailable for this hotel/)

    expect(room_revenue_code.transaction_code_taxes.reload.map(&:tax_rule_key)).to eq([ "primary:sst_tax" ])
  end

  it "refuses an unknown primary tax key" do
    expect {
      described_class.call(transaction_code: room_revenue_code, keys: [ "primary:vat" ])
    }.to raise_error(ArgumentError, /unavailable for this hotel/)
  end
end
