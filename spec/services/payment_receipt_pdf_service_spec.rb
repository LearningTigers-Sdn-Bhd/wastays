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

  it "wears the shared frame and carries the receipt party blocks" do
    text = text_of(described_class.new(receipt).generate)

    expect(text).to include(
      "Harbour View Hotel", "PAYER DETAILS", "Payer", "Address",
      "PAYMENT DETAILS", "Received", "Payment method", "Bank transfer",
      "Reference", "AR-PAY-9001", "AMOUNT RECEIVED", "Page 1 of 1"
    )
  end

  # A payer has an address, and an address needs its own lines. The metadata strip
  # holds one short value per label, so the receipt wears party blocks instead.
  it "prints the guest address on a booking receipt" do
    booking = create(:booking, hotel: hotel,
      guest_name: "Hanami Saki",
      guest_email: "sakihanami@example.com",
      guest_phone: "601212223344",
      guest_home_address: "Hatsuboshi Gakuen Dorm A",
      guest_city: "Hatsuboshi",
      guest_postal_code: "123221",
      guest_address_country: "Japan")
    booking_receipt = create(:deposit, hotel: hotel, booking: booking, amount: 50).receipt

    text = text_of(described_class.new(booking_receipt).generate)

    expect(text).to include(
      "PAYER DETAILS", "Hanami Saki", "Hatsuboshi Gakuen Dorm A", "123221 Hatsuboshi", "Japan",
      "CONTACT DETAILS", "sakihanami@example.com", "601212223344",
      "Booking no.", booking.formatted_reservation_number,
      "Confirmation", booking.confirmation_token
    )
  end

  # The address follows the guest record, so a clerical fix reaches every reprint.
  it "reprints a corrected guest address" do
    booking = create(:booking, hotel: hotel, guest_home_address: "Old address",
      guest_city: "Ipoh", guest_postal_code: "30000", guest_address_country: "Malaysia")
    booking_receipt = create(:deposit, hotel: hotel, booking: booking, amount: 50).receipt
    booking.update!(guest_home_address: "New address", guest_city: "Kuching", guest_postal_code: "93000")

    text = text_of(described_class.new(booking_receipt).generate)

    expect(text).to include("New address", "93000 Kuching")
    expect(text).not_to include("Old address")
  end

  it "leaves off the confidential mark it does not deserve" do
    expect(text_of(described_class.new(receipt).generate)).not_to include("Confidential")
  end

  it "drops the reference column rather than printing a placeholder" do
    receipt.update!(external_reference: nil)

    expect(text_of(described_class.new(receipt).generate)).not_to include("Reference")
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
