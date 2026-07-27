# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::RecordResult do
  it "carries the recorded deposit on success" do
    result = described_class.success(deposit: "deposit")

    expect(result).to be_success
    expect(result.deposit).to eq("deposit")
  end

  it "reports record failures without a deposit" do
    result = described_class.failure("Unable to record deposit")

    expect(result).not_to be_success
    expect(result.error).to eq("Unable to record deposit")
    expect(result.deposit).to be_nil
  end
end
