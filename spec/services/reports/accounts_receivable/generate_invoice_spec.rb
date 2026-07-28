# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe Reports::AccountsReceivable::GenerateInvoice do
  let(:hotel) { create(:hotel, name: "Snapshot Hotel", hotel_prefix: "ARP") }
  let(:booking) { create(:booking, hotel:, confirmation_token: "BK-AR-PDF", currency: "MYR") }
  let!(:room) { create(:booking_room, booking:, room_number: "501", room_type_snapshot: { "name" => "Executive Suite" }) }
  let(:relationship) do
    create(:hotel_corporate_account, :direct_bill,
      hotel:,
      corporate_account: create(:account, :corporate, name: "Acme Holdings"),
      account_type: "company",
      payment_terms_days: 30)
  end
  let(:party) { create(:booking_billing_party, :company, booking:, hotel:, hotel_corporate_account: relationship) }
  let(:folio) do
    create(:booking_folio, :secondary,
      booking:,
      hotel:,
      booking_billing_party: party,
      hotel_corporate_account: relationship,
      status: "closed",
      closed_at: Time.current)
  end

  before do
    create(:booking_billing_terms,
      booking_billing_party: party,
      settlement_type: "city_ledger",
      purchase_order_reference: "PO-7788",
      authorization_reference: "AUTH-22")
    code = create(:transaction_code, hotel:, code: "RM-AR", name: "Room Revenue", kind: "charge", category: "accommodation")
    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: code,
      amount: 450,
      description: "Executive Suite accommodation",
      posting_date: Date.new(2026, 7, 20))
  end

  it "renders the issued AR invoice details and current payment amounts" do
    invoice = Folios::Lifecycle::CreateDirectBillArInvoice.call!(folio:, balance: 450)
    invoice.update!(paid_amount: 125, outstanding_amount: 325, status: "partially_paid")

    text = pdf_text(described_class.new(invoice:, printed_by: "Finance User").generate)

    expect(text).to include("ACCOUNTS RECEIVABLE INVOICE")
    expect(text).to include(invoice.formatted_invoice_number)
    expect(text).to include("Acme Holdings", "Company", "BK-AR-PDF")
    expect(text).to include(folio.folio_reference_display, "501 / Executive Suite")
    expect(text).to include("PO-7788", "AUTH-22", "Net 30 days")
    expect(text).to include("Executive Suite accommodation", "RM-AR")
    expect(text).to include("450.00", "125.00", "325.00", "Partially paid")
    expect(text).to include("Printed at", "Finance User")
  end

  it "keeps issue-time payer and reference values after source records change" do
    invoice = Folios::Lifecycle::CreateDirectBillArInvoice.call!(folio:, balance: 450)
    relationship.corporate_account.update!(name: "Renamed Company")
    party.billing_terms.update!(purchase_order_reference: "PO-NEW")

    text = pdf_text(described_class.new(invoice:).generate)

    expect(text).to include("Acme Holdings", "PO-7788")
    expect(text).not_to include("Renamed Company", "PO-NEW")
  end

  it "keeps an issued blank authorization blank when it is populated later" do
    party.billing_terms.update!(authorization_reference: nil)
    invoice = Folios::Lifecycle::CreateDirectBillArInvoice.call!(folio:, balance: 450)
    party.billing_terms.update!(authorization_reference: "AUTH-LATE")

    text = pdf_text(described_class.new(invoice:).generate)

    expect(text).not_to include("AUTH-LATE")
  end

  it "reconciles pre-close payments to the balance transferred to AR" do
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "cash",
      amount: 150,
      description: "Advance corporate payment")
    invoice = Folios::Lifecycle::CreateDirectBillArInvoice.call!(folio:, balance: 300)

    records = Reports::AccountsReceivable::GenerateInvoiceRecords.new(invoice:)
    text = pdf_text(described_class.new(invoice:).generate)

    expect(records.line_total).to eq(invoice.amount)
    expect(text).to include("Payment - Advance corporate payment")
    expect(text).to include("-150.00")
    expect(text).to include("BALANCE TRANSFERRED TO AR", "300.00")
  end

  def pdf_text(pdf)
    PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
  end
end
