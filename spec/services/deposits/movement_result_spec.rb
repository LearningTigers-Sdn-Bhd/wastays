# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::MovementResult do
  it "carries the deposit, movement, and folio transaction" do
    result = described_class.success(deposit: "deposit", movement: "movement", transaction: "transaction")

    expect(result).to be_success
    expect(result).to have_attributes(deposit: "deposit", movement: "movement", transaction: "transaction")
  end

  it "nil-fills omitted values on failure" do
    result = described_class.failure("Unable to move deposit", deposit: "deposit")

    expect(result).not_to be_success
    expect(result).to have_attributes(error: "Unable to move deposit", deposit: "deposit", movement: nil, transaction: nil)
  end
end
