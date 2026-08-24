# frozen_string_literal: true

require "rails_helper"

RSpec.describe Receipts::Presentation do
  it "presents a refundable security deposit as money held" do
    receipt = create(:deposit).receipt
    presentation = described_class.new(receipt)

    expect(presentation).to have_attributes(
      security_deposit?: true,
      title: "Security Deposit Receipt",
      amount_label: "Amount held",
      note: described_class::SECURITY_DEPOSIT_NOTE,
      filename: "security-deposit-receipt-#{receipt.public_number}.pdf",
      email_subject: "Security deposit receipt #{receipt.public_number}",
      workspace_type: "Security deposit receipt"
    )
    expect(presentation.void_note).to include("no longer evidence of a security deposit received")
  end

  it "keeps prepayment receipts under the existing payment identity" do
    receipt = create(:deposit, :prepayment).receipt
    presentation = described_class.new(receipt)

    expect(presentation).to have_attributes(
      security_deposit?: false,
      title: "Payment Receipt",
      amount_label: "Amount received",
      note: described_class::PAYMENT_NOTE,
      filename: "payment-receipt-#{receipt.public_number}.pdf",
      email_subject: "Payment receipt #{receipt.public_number}",
      workspace_type: "Deposit receipt"
    )
  end

  it "distinguishes group security deposits in the booking workspace" do
    receipt = create(:deposit, :group_owned).receipt

    expect(described_class.new(receipt).workspace_type).to eq("Group security deposit receipt")
  end

  it "keeps non-deposit receipts under the existing payment identity" do
    receipt = create(:ar_payment).receipt

    expect(described_class.new(receipt)).to have_attributes(
      security_deposit?: false,
      title: "Payment Receipt",
      workspace_type: "Payment receipt"
    )
  end

  it "keeps folio-payment receipts under the existing payment identity" do
    booking = create(:booking)
    folio = create(:booking_folio, booking: booking, hotel: booking.hotel)
    receipt = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "cash",
      amount: 100
    ).receipt

    expect(described_class.new(receipt)).to have_attributes(
      security_deposit?: false,
      title: "Payment Receipt",
      amount_label: "Amount received",
      workspace_type: "Payment receipt"
    )
  end
end
