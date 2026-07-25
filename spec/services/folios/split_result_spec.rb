# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::SplitResult do
  it "reports both sides of the split, with the target side as the transaction" do
    result = described_class.success(
      source_transactions: [ "remainder" ],
      target_transactions: [ "split_off" ],
      transaction: "split_off",
      operation_key: "op-1"
    )

    expect(result).to be_success
    expect(result.source_transactions).to eq([ "remainder" ])
    expect(result.target_transactions).to eq([ "split_off" ])
    expect(result.transaction).to eq("split_off")
    expect(result.operation_key).to eq("op-1")
  end

  it "reports both sides as empty on failure" do
    result = described_class.failure("Split amount must be less than the transaction amount.", source_transactions: [], target_transactions: [])

    expect(result).not_to be_success
    expect(result.source_transactions).to eq([])
    expect(result.target_transactions).to eq([])
    expect(result.transaction).to be_nil
  end
end
