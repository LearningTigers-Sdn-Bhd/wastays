# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Snapshot do
  it "freezes folio transactions and issue-time totals" do
    folio = create(:booking_folio, status: "closed", currency: "MYR")
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 125)
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 25)

    snapshot = described_class.call(folio:)

    expect(snapshot.dig(:folio, :id)).to eq(folio.id)
    expect(snapshot.fetch(:transactions).size).to eq(2)
    expect(snapshot.fetch(:totals)).to include(charges: "125.0", payments: "25.0", balance: "100.0", currency: "MYR")
  end
end
