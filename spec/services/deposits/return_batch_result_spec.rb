# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::ReturnBatchResult do
  it "carries the returned deposit summary" do
    released_at = Time.current
    result = described_class.success(
      deposit_ids: [ 7, 9 ],
      total: 125.to_d,
      method: "bank_transfer",
      reference: "RETURN-1",
      released_at: released_at
    )

    expect(result).to be_success
    expect(result).to have_attributes(
      deposit_ids: [ 7, 9 ],
      total: 125.to_d,
      method: "bank_transfer",
      reference: "RETURN-1",
      released_at: released_at
    )
  end

  it "preserves an empty batch summary on failure" do
    result = described_class.failure("Deposit release failed", deposit_ids: [], total: 0.to_d)

    expect(result).not_to be_success
    expect(result).to have_attributes(error: "Deposit release failed", deposit_ids: [], total: 0.to_d)
  end
end
