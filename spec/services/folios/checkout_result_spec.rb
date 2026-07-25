# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::CheckoutResult do
  it "carries the primary folio and the balance across every folio" do
    result = described_class.success(folio: "F", balance: 250.to_d)

    expect(result).to be_success
    expect(result.folio).to eq("F")
    expect(result.balance).to eq(250.to_d)
  end

  it "reports the balance that blocked checkout on failure" do
    result = described_class.failure("Cannot check out with outstanding balance of RM250.00.", folio: "F", balance: 250.to_d)

    expect(result).not_to be_success
    expect(result.balance).to eq(250.to_d)
  end
end
