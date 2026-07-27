# frozen_string_literal: true

require "rails_helper"

RSpec.describe Deposits::BatchResult do
  it "carries applied movements on success" do
    result = described_class.success(movements: [ "movement" ])

    expect(result).to be_success
    expect(result.movements).to eq([ "movement" ])
    expect(result.error).to be_nil
  end

  it "provides an empty movement list on failure" do
    result = described_class.failure("Unable to apply deposit", movements: [])

    expect(result).not_to be_success
    expect(result.error).to eq("Unable to apply deposit")
    expect(result.movements).to eq([])
  end
end
