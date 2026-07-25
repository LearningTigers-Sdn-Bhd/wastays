# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioRouting::BatchResult do
  it "reports the transactions the change relocated" do
    result = described_class.success(transactions: [ "moved" ])

    expect(result).to be_success
    expect(result.transactions).to eq([ "moved" ])
    expect(result.error).to be_nil
  end

  it "reports an empty list on failure, so callers can concat unconditionally" do
    result = described_class.failure("Choose how to handle existing charges.", transactions: [])

    expect(result).not_to be_success
    expect(result.error).to eq("Choose how to handle existing charges.")
    expect(result.transactions).to eq([])
  end
end
