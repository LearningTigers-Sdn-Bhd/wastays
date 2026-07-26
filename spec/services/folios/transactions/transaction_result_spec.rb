# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Transactions::TransactionResult do
  it "carries a single posted transaction" do
    result = described_class.success(transaction: "T")

    expect(result).to be_success
    expect(result.transaction).to eq("T")
    expect(result.transactions).to be_nil
    expect(result.error).to be_nil
  end

  it "carries a parent and its tax lines together" do
    result = described_class.success(transaction: "parent", transactions: [ "parent", "tax" ])

    expect(result.transaction).to eq("parent")
    expect(result.transactions).to eq([ "parent", "tax" ])
  end

  it "attaches tax transactions onto an existing result without mutating it" do
    posted = described_class.success(transaction: "parent")
    taxed = posted.with(tax_transactions: [ "sst" ])

    expect(taxed.transaction).to eq("parent")
    expect(taxed.tax_transactions).to eq([ "sst" ])
    expect(posted.tax_transactions).to be_nil
  end

  it "carries only the error on failure" do
    result = described_class.failure("Amount must be greater than zero.")

    expect(result).not_to be_success
    expect(result.error).to eq("Amount must be greater than zero.")
    expect(result.transaction).to be_nil
  end
end
