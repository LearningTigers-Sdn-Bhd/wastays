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

  it "moves generated tax children to explicit tax target folios" do
    tax_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
    parent = create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")
    tax = create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "tax", amount: 10, description: "Tourism Tax", metadata: { parent_folio_transaction_id: parent.id, tax_line: { type: "tourism_tax" } })

    result = described_class.call(
      transaction: parent,
      target_folio: target_folio,
      user: user,
      reason: "Company pays room, guest pays tax",
      tax_routes: { tax.id => tax_folio.id }
    )

    expect(result).to be_success
    moved_parent, moved_tax = result.transactions
    expect(parent.reload.voided_by_transaction).to be_present
    expect(tax.reload.voided_by_transaction).to be_present
    expect(moved_parent.booking_folio).to eq(target_folio)
    expect(moved_tax.booking_folio).to eq(tax_folio)
    expect(moved_tax.metadata["parent_folio_transaction_id"]).to eq(moved_parent.id)
    expect(moved_tax.parent_transaction).to be_nil
  end

  it "moves nightly-style tax rows linked by source transaction code" do
    room_code = create(:transaction_code, hotel: hotel, code: "ROOM-N", name: "Room", kind: "charge", category: "accommodation")
    tax_code = create(:transaction_code, hotel: hotel, code: "TTX-N", name: "Tourism Tax", kind: "charge", category: "tax")
    tax_folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel)
    parent = create(:folio_transaction,
      booking_folio: source_folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 740,
      description: "Room Charge",
      posting_date: Date.current,
      transaction_code: room_code,
      metadata: { stay_date: Date.current.iso8601 })
    tax = create(:folio_transaction,
      booking_folio: source_folio,
      transaction_type: "charge",
      category: "tax",
      amount: 10,
      description: "Tourism Tax",
      posting_date: Date.current,
      transaction_code: tax_code,
      metadata: { stay_date: Date.current.iso8601, tax_line: { type: "tourism_tax", source_transaction_code_id: room_code.id } })

    result = described_class.call(
      transaction: parent,
      target_folio: target_folio,
      user: user,
      reason: "Company pays room, guest pays tax",
      tax_routes: { tax.id => tax_folio.id }
    )

    expect(result).to be_success
    moved_parent, moved_tax = result.transactions
    expect(moved_parent.booking_folio).to eq(target_folio)
    expect(moved_tax.booking_folio).to eq(tax_folio)
    expect(tax.reload.voided_by_transaction).to be_present
  end

  it "does not copy unique nightly posting keys onto move reversal rows" do
    charge = create(:folio_transaction,
      booking_folio: source_folio,
      transaction_type: "charge",
      category: "accommodation",
      amount: 740,
      description: "Room Charge",
      metadata: { nightly_charge_key: "#{booking.id}:2026-06-23:accommodation:314" })

    result = described_class.call(transaction: charge, target_folio: target_folio, user: user, reason: "Company pays room")

    expect(result).to be_success
    expect(charge.reload.voided_by_transaction.metadata).not_to include("nightly_charge_key")
    expect(result.transaction.metadata["nightly_charge_key"]).to eq("#{booking.id}:2026-06-23:accommodation:314")
  end

  it "rejects tax routes for transactions outside the attached tax group" do
    parent = create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "accommodation", amount: 740, description: "Room Charge")
    unrelated_tax = create(:folio_transaction, booking_folio: source_folio, transaction_type: "charge", category: "tax", amount: 10, description: "Tourism Tax")

    result = described_class.call(
      transaction: parent,
      target_folio: target_folio,
      user: user,
      reason: "Company pays room",
      tax_routes: { unrelated_tax.id => target_folio.id }
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Tax routes can only target attached tax rows for this transaction.")
  end
end
