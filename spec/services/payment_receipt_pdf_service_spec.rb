# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe PaymentReceiptPdfService do
  let(:hotel) { create(:hotel, name: "Harbour View Hotel") }
  let(:receipt) do
    create(:ar_payment,
      hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel),
      amount: 1234.50, currency: "MYR", payment_method: "bank_transfer",
      reference_number: "AR-PAY-9001").receipt
  end

  def text_of(pdf) = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

  def info_of(pdf) = PDF::Reader.new(StringIO.new(pdf)).info

  it "renders the immutable payment receipt reference and amount" do
    pdf = described_class.new(receipt).generate

    expect(pdf).to start_with("%PDF")
    expect(text_of(pdf)).to include("PAYMENT RECEIPT", receipt.public_number, "MYR 1,234.50")
  end

  it "wears the shared frame and carries the receipt metadata" do
    text = text_of(described_class.new(receipt).generate)

    expect(text).to include(
      "Harbour View Hotel", "RECEIVED", "PAYER", "PAYMENT METHOD", "Bank transfer",
      "REFERENCE", "AR-PAY-9001", "AMOUNT RECEIVED", "Page 1 of 1"
    )
  end

  it "leaves off the confidential mark it does not deserve" do
    expect(text_of(described_class.new(receipt).generate)).not_to include("Confidential")
  end

  it "drops the reference column rather than printing a placeholder" do
    receipt.update!(external_reference: nil)

    expect(text_of(described_class.new(receipt).generate)).not_to include("REFERENCE")
  end

  it "marks a voided receipt before the amount" do
    receipt.update!(status: "voided")
    text = text_of(described_class.new(receipt).generate)

    expect(text).to include("VOIDED", "no longer evidence of a payment received")
    expect(text.index("VOIDED")).to be < text.index("AMOUNT RECEIVED")
  end

  it "leaves an issued receipt unbanded" do
    expect(text_of(described_class.new(receipt).generate)).not_to include("VOIDED")
  end

  it "presents a security deposit as refundable money held" do
    security_receipt = create(:deposit, hotel: hotel, booking: create(:booking, hotel: hotel), amount: 50).receipt
    pdf = described_class.new(security_receipt).generate
    text = text_of(pdf)

    expect(text).to include(
      "SECURITY DEPOSIT RECEIPT", "AMOUNT HELD", "MYR 50.00",
      Receipts::Presentation::SECURITY_DEPOSIT_NOTE
    )
    expect(text).not_to include("AMOUNT RECEIVED")
    expect(info_of(pdf)[:Title]).to eq("Security Deposit Receipt - #{security_receipt.public_number}")
  end

  it "keeps prepayments under the existing payment receipt identity" do
    prepayment_receipt = create(:deposit, :prepayment, hotel: hotel, booking: create(:booking, hotel: hotel)).receipt
    text = text_of(described_class.new(prepayment_receipt).generate)

    expect(text).to include("PAYMENT RECEIPT", "AMOUNT RECEIVED", Receipts::Presentation::PAYMENT_NOTE)
    expect(text).not_to include("SECURITY DEPOSIT RECEIPT", "AMOUNT HELD")
  end

  it "uses security-deposit wording when a security receipt is voided" do
    security_receipt = create(:deposit, hotel: hotel, booking: create(:booking, hotel: hotel)).receipt
    security_receipt.update!(status: "voided")
    text = text_of(described_class.new(security_receipt).generate)

    expect(text).to include("VOIDED", "no longer evidence of a security deposit received")
    expect(text.index("VOIDED")).to be < text.index("AMOUNT HELD")
  end
end
