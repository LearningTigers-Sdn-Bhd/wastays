# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Transactions::MoveResult do
  it "reports every moved transaction, the parent first, and the operation key" do
    result = described_class.success(transactions: [ "parent", "tax" ], transaction: "parent", operation_key: "op-1")

    expect(result).to be_success
    expect(result.transactions).to eq([ "parent", "tax" ])
    expect(result.transaction).to eq("parent")
    expect(result.operation_key).to eq("op-1")
  end

  it "reports nothing moved on failure, so callers can concat the list unconditionally" do
    result = described_class.failure("Target folio is closed.", transactions: [])

    expect(result).not_to be_success
    expect(result.error).to eq("Target folio is closed.")
    expect(result.transactions).to eq([])
    expect(result.transaction).to be_nil
  end
end
