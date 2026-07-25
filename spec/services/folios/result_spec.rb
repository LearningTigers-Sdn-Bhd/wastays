# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Result do
  it "carries the folio on success" do
    result = described_class.success(folio: "F")

    expect(result).to be_success
    expect(result.folio).to eq("F")
    expect(result.error).to be_nil
  end

  it "still carries the folio on failure, so callers can redirect back to it" do
    result = described_class.failure("Closed or voided folios cannot be edited.", folio: "F")

    expect(result).not_to be_success
    expect(result.folio).to eq("F")
    expect(result.error).to eq("Closed or voided folios cannot be edited.")
  end
end
