# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioRouting::GroupBatchPreview do
  it "carries one entry per sibling booking and the totals across them" do
    preview = described_class.success(
      bookings: [ { booking: "B", preview: "P" } ], count: 3, amount: 300.to_d,
      upcoming_count: 0, upcoming_amount: 0.to_d, "review_required?": true
    )

    expect(preview).to be_success
    expect(preview.bookings.size).to eq(1)
    expect(preview.count).to eq(3)
    expect(preview.review_required?).to be(true)
  end

  it "leaves the totals unset on failure" do
    preview = described_class.failure("Booking No. 12: Select a folio for every routed code.")

    expect(preview).not_to be_success
    expect(preview.bookings).to be_nil
    expect(preview.review_required?).to be_nil
  end
end
