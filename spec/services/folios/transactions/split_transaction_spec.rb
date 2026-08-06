# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Transactions::SplitTransaction do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:user) { create(:user, :superadmin) }
  let(:source_folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let(:target_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel) }

  it "splits a posted charge between source and target folios" do
    charge = create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")

    result = described_class.call(transaction: charge, target_folio: target_folio, user: user, reason: "Split company responsibility", percent: 50)

    expect(result).to be_success
    expect(charge.reload.voided_by_transaction).to be_present
    expect(result.source_transactions.first.amount).to eq(370.to_d)
    expect(result.target_transactions.first.amount).to eq(370.to_d)
    expect(result.target_transactions.first.split_from_transaction).to eq(charge)
    expect(FolioOperationLog.last.operation_type).to eq("split_transaction")
  end

  it "splits generated tax children proportionally" do
    parent = create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")
    create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "tax", amount: 59.20, description: "SST", metadata: { parent_folio_transaction_id: parent.id, tax_line: { type: "sst" } })

    result = described_class.call(transaction: parent, target_folio: target_folio, user: user, reason: "Split company responsibility", amount: 370)

    expect(result).to be_success
    source_tax = result.source_transactions.second
    target_tax = result.target_transactions.second
    expect(source_tax.amount).to eq(29.60.to_d)
    expect(target_tax.amount).to eq(29.60.to_d)
    expect(source_tax.metadata["parent_folio_transaction_id"]).to eq(result.source_transactions.first.id)
    expect(target_tax.metadata["parent_folio_transaction_id"]).to eq(result.target_transactions.first.id)
  end
end
