# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionCodeTax, type: :model do
  it { is_expected.to belong_to(:transaction_code) }
  it { is_expected.to belong_to(:hotel_tax).optional }

  it "requires the tax to belong to the transaction code hotel" do
    transaction_code = create(:transaction_code)
    hotel_tax = create(:hotel_tax)

    rule = described_class.new(transaction_code: transaction_code, hotel_tax: hotel_tax)

    expect(rule).not_to be_valid
    expect(rule.errors[:hotel_tax]).to include("must belong to the same hotel as the transaction code")
  end

  it "allows a primary tax rule without a hotel tax" do
    rule = build(:transaction_code_tax, hotel_tax: nil, primary_tax_key: "sst_tax")

    expect(rule).to be_valid
    expect(rule.tax_rule_key).to eq("primary:sst_tax")
  end

  it "requires exactly one tax source" do
    rule = build(:transaction_code_tax, hotel_tax: nil, primary_tax_key: nil)

    expect(rule).not_to be_valid
    expect(rule.errors[:base]).to include("must reference either a hotel tax or a primary tax")
  end
end
