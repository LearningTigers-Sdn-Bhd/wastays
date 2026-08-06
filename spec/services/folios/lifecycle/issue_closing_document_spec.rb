# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Lifecycle::IssueClosingDocument do
  it "returns one settled invoice without a receivable" do
    folio = create(:booking_folio, status: "closed")

    outcome = described_class.call!(folio:, settlement_method: "cash", balance: 0, user: nil)

    expect(outcome.invoice).to be_kind_settled
    expect(outcome.receivable).to be_nil
  end

  it "returns a direct-bill invoice with its receivable" do
    folio = create(:booking_folio, :secondary, status: "closed")

    outcome = described_class.call!(folio:, settlement_method: "direct_bill", balance: 100, user: nil)

    expect(outcome.invoice).to be_kind_direct_bill
    expect(outcome.receivable.invoice).to eq(outcome.invoice)
  end
end
