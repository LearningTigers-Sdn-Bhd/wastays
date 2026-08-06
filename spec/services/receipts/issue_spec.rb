# frozen_string_literal: true

require "rails_helper"

RSpec.describe Receipts::Issue do
  it "issues one receipt for an individual folio payment" do
    folio = create(:booking_folio)

    transaction = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "cash",
      amount: 45,
      posted_at: Time.current
    )

    receipt = transaction.receipt
    expect(receipt).to be_present
    expect(receipt.amount).to eq(45.to_d)
    expect(receipt.public_number).to match(/-\d{2}5\d{5}\z/)
  end

  it "returns the existing receipt without consuming another number" do
    transaction = create(
      :folio_transaction,
      transaction_type: "payment",
      category: "cash",
      amount: 45
    )
    original = transaction.receipt
    counter_value = HotelCounter.find_by!(hotel: transaction.hotel, counter_type: "receipt", sequence_year: original.receipt_year).last_value

    repeated = described_class.call!(source: transaction)

    expect(repeated).to eq(original)
    expect(HotelCounter.find_by!(hotel: transaction.hotel, counter_type: "receipt", sequence_year: original.receipt_year).last_value).to eq(counter_value)
  end

  it "does not attach gateway provenance from another hotel" do
    other_hotel = create(:hotel)
    payment_transaction = create(:payment_transaction, booking_quote: create(:booking_quote, hotel: other_hotel))
    transaction = create(
      :folio_transaction,
      transaction_type: "payment",
      category: "gateway_payment",
      amount: 45,
      metadata: { payment_transaction_id: payment_transaction.id }
    )

    expect(transaction.receipt.payment_transaction).to be_nil
    expect(transaction.receipt.payment_method).to eq("gateway_payment")
  end

  it "does not issue another receipt for a deposit application" do
    transaction = create(
      :folio_transaction,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 45,
      metadata: { deposit_id: 123 }
    )

    expect(transaction.receipt).to be_nil
  end

  it "issues a receipt for a deposit when money is received" do
    deposit = create(:deposit, :prepayment)

    expect(deposit.receipt).to be_present
    expect(deposit.receipt.amount).to eq(deposit.amount)
  end

  it "does not issue a receipt for a pending deposit" do
    deposit = create(:deposit, status: "pending")

    expect(deposit.receipt).to be_nil
  end

  it "issues a receipt when a pending deposit becomes received" do
    deposit = create(:deposit, status: "pending")

    expect { deposit.update!(status: "available") }.to change(Receipt, :count).by(1)
    expect(deposit.reload.receipt).to be_present
  end

  it "issues a receipt for an AR payment rather than each allocation" do
    payment = create(:ar_payment)

    expect(payment.receipt).to be_present
    expect(payment.receipt.amount).to eq(payment.amount)
  end
end
