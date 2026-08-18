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
end
