# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::ReverseTransaction do
  let(:user) { create(:user) }
  let(:booking) { create(:booking, currency: "MYR") }
  let(:folio) { create(:booking_folio, booking: booking, hotel: booking.hotel, status: "open") }

  it "reverses a charge with an offsetting correction transaction" do
    charge = create(:folio_transaction, booking_folio: folio, amount: 100.0, transaction_type: :charge, category: "accommodation")

    result = described_class.call(
      transaction: charge,
      user: user,
      correction_reason: "Wrong charge",
      correction_note: "Posted to the wrong reservation"
    )

    expect(result).to be_success
    reversal = result.transaction
    expect(reversal).to be_adjustment
    expect(reversal.category).to eq("correction")
    expect(reversal.amount).to eq(-100.0)
    expect(reversal.reversal_of_transaction).to eq(charge)
    expect(reversal.correction_reason).to eq("Wrong charge")
    expect(reversal.correction_note).to eq("Posted to the wrong reservation")
    expect(reversal.currency).to eq("MYR")
    expect(charge.reload.voided_by_transaction).to eq(reversal)
    expect(folio.outstanding_balance).to eq(0)
  end

  it "reverses a payment with a refund transaction" do
    payment = create(:folio_transaction, booking_folio: folio, amount: 75.0, transaction_type: :payment, category: "cash")

    result = described_class.call(
      transaction: payment,
      user: user,
      correction_reason: "Payment error",
      correction_note: "Cash was posted twice"
    )

    expect(result).to be_success
    reversal = result.transaction
    expect(reversal).to be_payment
    expect(reversal.category).to eq("refund")
    expect(reversal.amount).to eq(-75.0)
    expect(payment.reload.voided_by_transaction).to eq(reversal)
    expect(folio.outstanding_balance).to eq(0)
  end

  it "rejects a second reversal" do
    charge = create(:folio_transaction, booking_folio: folio, amount: 100.0, transaction_type: :charge, category: "accommodation")

    described_class.call(transaction: charge, user: user, correction_reason: "Wrong", correction_note: "First reversal")
    result = described_class.call(transaction: charge.reload, user: user, correction_reason: "Wrong", correction_note: "Second reversal")

    expect(result).not_to be_success
    expect(result.error).to eq("Transaction has already been reversed.")
  end

  it "rejects reversing a reversal transaction" do
    charge = create(:folio_transaction, booking_folio: folio, amount: 100.0, transaction_type: :charge, category: "accommodation")
    reversal = described_class.call(transaction: charge, user: user, correction_reason: "Wrong", correction_note: "First reversal").transaction

    result = described_class.call(transaction: reversal, user: user, correction_reason: "Wrong", correction_note: "Reverse reversal")

    expect(result).not_to be_success
    expect(result.error).to eq("Reversal transactions cannot be reversed.")
  end

  it "respects closed folio guards" do
    folio.update!(status: "closed")
    charge = create(:folio_transaction, booking_folio: folio, amount: 100.0, transaction_type: :charge, category: "accommodation")

    result = described_class.call(transaction: charge, user: user, correction_reason: "Wrong", correction_note: "Closed folio")

    expect(result).not_to be_success
    expect(result.error).to include("Folio is closed")
  end

  it "respects closed business date guards" do
    closed_date = 1.day.ago.to_date
    create(:night_audit, hotel: booking.hotel, business_date: closed_date, status: "completed")
    charge = create(:folio_transaction, booking_folio: folio, amount: 100.0, transaction_type: :charge, category: "accommodation")

    result = described_class.call(
      transaction: charge,
      user: user,
      correction_reason: "Wrong",
      correction_note: "Closed date",
      posting_date: closed_date
    )

    expect(result).not_to be_success
    expect(result.error).to include("business date #{closed_date} is already closed")
  end

  it "stores posting metadata for the reversal" do
    charge = create(:folio_transaction, booking_folio: folio, amount: 100.0, transaction_type: :charge, category: "accommodation")

    result = described_class.call(transaction: charge, user: user, correction_reason: "Wrong", correction_note: "Metadata check")

    expect(result.transaction.posted_at).to be_present
    expect(result.transaction.metadata).to include(
      "posting_source" => "folio_reversal",
      "reversed_transaction_id" => charge.id,
      "posted_by_user_id" => user.id
    )
  end
end
