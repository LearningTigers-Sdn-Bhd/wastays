# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::BatchPreview do
  it "carries the changes and the totals the impact screen renders" do
    preview = described_class.success(
      changes: [ "c" ], child_changes: [], tax_changes: [], impacts: [ "i" ],
      count: 2, amount: 150.to_d, upcoming_count: 1, upcoming_amount: 50.to_d,
      "review_required?": true
    )

    expect(preview).to be_success
    expect(preview.review_required?).to be(true)
    expect(preview.count).to eq(2)
    expect(preview.upcoming_amount).to eq(50.to_d)
  end

  it "leaves review_required? unset on failure, so the impact screen stays hidden" do
    preview = described_class.failure("Select a folio for every routed code.")

    expect(preview).not_to be_success
    expect(preview.error).to eq("Select a folio for every routed code.")
    expect(preview.review_required?).to be_nil
    expect(preview.impacts).to be_nil
  end
end
