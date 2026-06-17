# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransactionCodeTax, type: :model do
  it { is_expected.to belong_to(:transaction_code) }
  it { is_expected.to belong_to(:hotel_tax) }

  it "requires the tax to belong to the transaction code hotel" do
    transaction_code = create(:transaction_code)
    hotel_tax = create(:hotel_tax)

    rule = described_class.new(transaction_code: transaction_code, hotel_tax: hotel_tax)

    expect(rule).not_to be_valid
    expect(rule.errors[:hotel_tax]).to include("must belong to the same hotel as the transaction code")
  end
end
