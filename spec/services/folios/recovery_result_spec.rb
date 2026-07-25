# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::RecoveryResult do
  it "separates a folio it built from one that was already there" do
    built = described_class.success(folio: "F", "created?": true, message: "Folio recovered.")
    found = described_class.success(folio: "F", "created?": false, message: "Folio already exists.")

    expect(built).to be_success
    expect(built.created?).to be(true)
    expect(built.message).to eq("Folio recovered.")

    expect(found).to be_success
    expect(found.created?).to be(false)
    expect(found.message).to eq("Folio already exists.")
  end

  it "repeats the error as the message on failure" do
    result = described_class.failure("Booking does not belong to this hotel.", "created?": false, message: "Booking does not belong to this hotel.")

    expect(result).not_to be_success
    expect(result.created?).to be(false)
    expect(result.message).to eq("Booking does not belong to this hotel.")
  end
end
