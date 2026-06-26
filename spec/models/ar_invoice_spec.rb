# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArInvoice, type: :model do
  it "requires folio and hotel corporate account to belong to the invoice hotel" do
    hotel = create(:hotel)
    other_hotel = create(:hotel)
    folio = create(:booking_folio, :secondary, hotel: hotel, booking: create(:booking, hotel: hotel))
    relationship = create(:hotel_corporate_account, hotel: other_hotel)

    invoice = build(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship)

    expect(invoice).not_to be_valid
    expect(invoice.errors[:hotel_corporate_account]).to include("must belong to the invoice hotel")
  end

  it "delegates booking and corporate account from canonical references" do
    invoice = create(:ar_invoice)

    expect(invoice.booking).to eq(invoice.booking_folio.booking)
    expect(invoice.corporate_account).to eq(invoice.hotel_corporate_account.corporate_account)
  end

  it "formats the AR invoice number with hotel prefix and type code 4" do
    hotel = create(:hotel, hotel_prefix: "ABC")
    relationship = create(:hotel_corporate_account, hotel: hotel)
    folio = create(:booking_folio, :secondary, hotel: hotel, booking: create(:booking, hotel: hotel), hotel_corporate_account: relationship)
    invoice = create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, invoice_number: 42)

    expect(invoice.formatted_invoice_number).to eq("ABC-40000042")
  end

  it "requires the invoice company account to match the folio company account" do
    hotel = create(:hotel)
    relationship = create(:hotel_corporate_account, hotel: hotel)
    other_relationship = create(:hotel_corporate_account, hotel: hotel)
    folio = create(:booking_folio, :secondary, hotel: hotel, booking: create(:booking, hotel: hotel), hotel_corporate_account: relationship)

    invoice = build(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: other_relationship)

    expect(invoice).not_to be_valid
    expect(invoice.errors[:hotel_corporate_account]).to include("must match the folio company account")
  end

  it "allows payment and status fields to change after creation" do
    invoice = create(:ar_invoice, amount: 100, paid_amount: 0, outstanding_amount: 100)

    expect {
      invoice.update!(paid_amount: 40, outstanding_amount: 60, status: "partially_paid")
    }.to change { invoice.reload.status }.from("open").to("partially_paid")

    expect(invoice.paid_amount).to eq(40.to_d)
    expect(invoice.outstanding_amount).to eq(60.to_d)
  end

  it "prevents immutable source fields changing after creation" do
    invoice = create(:ar_invoice)

    expect(invoice.update(amount: 200)).to eq(false)
    expect(invoice.errors[:base]).to include("AR invoices are immutable after creation except payment and status fields.")
    expect(invoice.reload.amount).to eq(100.to_d)
  end

  it "detects overdue open balances" do
    invoice = create(:ar_invoice, status: "open", outstanding_amount: 100, due_on: Date.current - 1.day)

    expect(invoice.overdue_as_of?(Date.current)).to eq(true)
  end
end
