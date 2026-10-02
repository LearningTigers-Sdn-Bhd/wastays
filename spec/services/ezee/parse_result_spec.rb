# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::ParseResult do
  it "succeeds when it carries no error" do
    expect(described_class.new(rows: [], warnings: [], layout: :reservation_csv)).to be_success
  end

  it "fails when it carries an error, which refuses the file" do
    result = described_class.new(rows: [], warnings: [], error: "No reservations found.")

    expect(result).not_to be_success
    expect(result.error).to eq("No reservations found.")
  end

  it "treats a blank error as no error" do
    expect(described_class.new(rows: [], warnings: [], error: "")).to be_success
  end
end
