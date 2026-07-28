# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe PaymentReceiptPdfService do
  it "renders the immutable payment receipt reference and amount" do
    payment = create(:ar_payment, amount: 123.45, currency: "MYR")
    receipt = payment.receipt

    pdf = described_class.new(receipt).generate
    text = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

    expect(text).to include("PAYMENT RECEIPT", receipt.public_number, "MYR 123.45")
  end
end
