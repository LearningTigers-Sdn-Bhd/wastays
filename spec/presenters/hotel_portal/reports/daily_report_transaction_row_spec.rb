# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyReportTransactionRow do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Jane Doe") }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }

  it "preserves a custom service identity" do
    code = create(:transaction_code, hotel: hotel, code: "ISLAND_HOP", name: "Island Hopping", kind: "charge", category: "other")
    transaction = create(:folio_transaction, booking_folio: folio, transaction_code: code, category: "other", amount: 100, description: "Two guests")
    row = described_class.new(transaction)

    expect(row.transaction_code).to eq("ISLAND_HOP")
    expect(row.service_name).to eq("Island Hopping")
    expect(row.signed_amount).to eq(100.to_d)
  end

  it "falls back to category and description when a transaction code is missing" do
    transaction = create(:folio_transaction, booking_folio: folio, category: "accommodation", description: "Room charge")
    transaction.update_column(:transaction_code_id, nil)
    row = described_class.new(transaction.reload)

    expect(row.transaction_code).to eq("—")
    expect(row.service_name).to eq("Room charge")
  end

  it "extracts payment method and posting source from metadata" do
    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "cash",
      amount: 50,
      metadata: { "payment_source" => "front_desk", "posting_source" => "manual" }
    )
    row = described_class.new(transaction)

    expect(row.payment_method).to eq("front_desk")
    expect(row.posting_source).to eq("manual")
  end

  it "uses a resolved cashier mode when supplied" do
    transaction = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "refund", amount: -25)

    row = described_class.new(transaction, settlement_mode: "Cash Payment")

    expect(row.settlement_mode).to eq("Cash Payment")
  end

  it "identifies automated gateway receipts without treating the gateway as a user" do
    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 50,
      user: nil,
      metadata: { payment_transaction_id: 42, posting_source: "gateway_payment" }
    )

    expect(described_class.new(transaction).received_by).to eq("Payment Gateway")
  end

  it "uses the staff name for manual receipts and an em dash for unattributed records" do
    staff = create(:user, name: "Aisha Cashier")
    manual = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 50, user: staff)
    legacy = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 50, user: nil, metadata: {})

    expect(described_class.new(manual).received_by).to eq("Aisha Cashier")
    expect(described_class.new(legacy).received_by).to eq("—")
  end

  it "reports relationship status for original, reversed, and reversal rows" do
    original = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100)
    reversal = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "adjustment",
      category: "correction",
      amount: -100,
      reversal_of_transaction: original
    )
    original.update_column(:voided_by_transaction_id, reversal.id)

    expect(described_class.new(original.reload).relationship_status).to eq("Reversed")
    expect(described_class.new(reversal).relationship_status).to eq("Reversal")

    untouched = create(:folio_transaction, booking_folio: folio, category: "tax", amount: 5)
    expect(described_class.new(untouched).relationship_status).to eq("Original")
  end

  it "handles a legacy row with no user" do
    transaction = create(:folio_transaction, booking_folio: folio, user: nil, category: "accommodation", amount: 100)
    row = described_class.new(transaction)

    expect(row.actor_name).to eq("—")
    expect(row.room_number).to eq("—")
  end

  it "formats the booked room number and snapshotted room type compactly" do
    room_type = create(:room_type, hotel: hotel, name: "Current Deluxe King")
    booking_room = create(
      :booking_room,
      booking: booking,
      room_type: room_type,
      room_number: "G01",
      room_type_snapshot: { "name" => "Booked Deluxe King" }
    )
    folio.update!(booking_room: booking_room)
    transaction = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100)

    row = described_class.new(transaction)

    expect(row.room_type_name).to eq("Booked Deluxe King")
    expect(row.room_details).to eq("G01 · Booked Deluxe King")
  end

  it "shows only the room type when no room number is assigned" do
    room_type = create(:room_type, hotel: hotel, name: "Deluxe King")
    booking_room = create(:booking_room, booking: booking, room_type: room_type, room_number: nil)
    folio.update!(booking_room: booking_room)
    transaction = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100)

    expect(described_class.new(transaction).room_details).to eq("Deluxe King")
  end

  it "omits room details when the booking has no room" do
    transaction = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100)

    expect(described_class.new(transaction).room_details).to be_nil
  end

  it "exposes the folio invoice number, falling back to an em dash" do
    hotel = create(:hotel)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel, invoice_number: 20260007)
    transaction = create(:folio_transaction, booking_folio: folio, category: "accommodation", amount: 100)

    row = described_class.new(transaction)

    expect(row.invoice_number).to eq(20260007)

    folio.update_columns(invoice_number: nil, invoice_year: nil)
    expect(described_class.new(transaction.reload).invoice_number).to eq("—")
  end
end
