# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReceiptMailer, type: :mailer do
  it "emails security-specific copy and attachment for a refundable deposit" do
    receipt = create(:deposit, booking: create(:booking, guest_email: "guest@example.com")).receipt
    mail = described_class.payment_receipt(receipt)

    expect(mail.to).to eq([ "guest@example.com" ])
    expect(mail.subject).to eq("Security deposit receipt #{receipt.public_number}")
    expect(mail.attachments.first.filename).to eq("security-deposit-receipt-#{receipt.public_number}.pdf")
    expect(mail.body.encoded).to include("refundable security deposit", "Amount held", "security deposit receipt is attached")
  end

  it "keeps normal payment copy and attachment for a prepayment" do
    receipt = create(:deposit, :prepayment, booking: create(:booking, guest_email: "guest@example.com")).receipt
    mail = described_class.payment_receipt(receipt)

    expect(mail.subject).to eq("Payment receipt #{receipt.public_number}")
    expect(mail.attachments.first.filename).to eq("payment-receipt-#{receipt.public_number}.pdf")
    expect(mail.body.encoded).to include("We received your payment", "Amount received", "individual payment receipt is attached")
    expect(mail.body.encoded).not_to include("refundable security deposit")
  end
end
