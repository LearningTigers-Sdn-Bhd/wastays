# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::RuleResult do
  it "carries the saved rule" do
    result = described_class.success(rule: "R")

    expect(result).to be_success
    expect(result.rule).to eq("R")
  end

  it "carries no rule on failure" do
    result = described_class.failure("Select a billing party.")

    expect(result).not_to be_success
    expect(result.rule).to be_nil
    expect(result.error).to eq("Select a billing party.")
  end
end
