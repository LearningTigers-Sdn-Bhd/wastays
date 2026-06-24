# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::MoveTransaction do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }
  let(:user) { create(:user, :superadmin) }
  let(:source_folio) { create(:booking_folio, booking: booking, hotel: hotel) }
  let(:target_folio) { create(:booking_folio, :secondary, booking: booking, hotel: hotel) }

  it "reverses a posted charge and reposts it on the target folio with lineage" do
    charge = create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")

    expect {
      @result = described_class.call(transaction: charge, target_folio: target_folio, user: user, reason: "Company pays room")
    }.to change(FolioTransaction, :count).by(2).and change(FolioOperationLog, :count).by(1)

    expect(@result).to be_success
    moved = @result.transaction
    expect(charge.reload.voided_by_transaction).to be_present
    expect(moved.booking_folio).to eq(target_folio)
    expect(moved.moved_from_transaction).to eq(charge)
    expect(moved.transfer_group_id).to be_present
    expect(FolioOperationLog.last.operation_type).to eq("move_transaction")
  end

  it "moves generated tax children with the parent charge" do
    parent = create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")
    tax = create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "tax", amount: 59.20, description: "SST", metadata: { parent_folio_transaction_id: parent.id, tax_line: { type: "sst" } })

    result = described_class.call(transaction: parent, target_folio: target_folio, user: user, reason: "Company pays room")

    expect(result).to be_success
    moved_parent, moved_tax = result.transactions
    expect(parent.reload.voided_by_transaction).to be_present
    expect(tax.reload.voided_by_transaction).to be_present
    expect(moved_parent.booking_folio).to eq(target_folio)
    expect(moved_tax.booking_folio).to eq(target_folio)
    expect(moved_tax.metadata["parent_folio_transaction_id"]).to eq(moved_parent.id)
  end
end
