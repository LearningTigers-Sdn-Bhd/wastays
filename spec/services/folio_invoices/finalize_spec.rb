# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioInvoices::Finalize do
  let(:booking) { create(:booking, currency: "MYR") }
  let(:user) { create(:user) }
  let(:folio) { create(:booking_folio, booking:, status: "closed", closed_at: Time.current, closed_by: user) }

  it "allocates one registry identifier and snapshots the finalized invoice" do
    create(:folio_transaction, booking_folio: folio, transaction_type: :charge, amount: 100)
    create(:folio_transaction, booking_folio: folio, transaction_type: :payment, category: "cash", amount: 100)

    expect {
      @invoice = described_class.call!(folio:, issued_by: user, balance: 0)
    }.to change(FolioInvoice, :count).by(1)
      .and change(FolioInvoiceRevision, :count).by(1)

    invoice = @invoice
    expect(invoice).to be_finalized
    expect(invoice.invoice_reference).to eq(folio.reload.invoice_reference)
    expect(invoice.current_revision.document_reference).to eq(invoice.invoice_reference)
    expect(invoice.current_revision.snapshot).to include(
      "folio" => include("id" => folio.id, "currency" => "MYR"),
      "totals" => include("charges" => "100.0", "payments" => "100.0", "balance" => "0.0")
    )
  end

  it "keeps the base identifier and appends a revision suffix after correction" do
    invoice = described_class.call!(folio:, issued_by: user, balance: 0)
    base_reference = invoice.invoice_reference
    invoice.update!(state: "under_correction")

    revised = described_class.call!(folio:, issued_by: user, balance: 0)

    expect(revised.reload.current_revision_number).to eq(2)
    expect(revised.invoice_reference).to eq(base_reference)
    expect(revised.current_revision.document_reference).to eq("#{base_reference}-2")
    expect(revised.revisions.pluck(:revision_number)).to eq([ 1, 2 ])
  end

  it "rejects a folio backed by an AR invoice" do
    relationship = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel)
    company_folio = create(:booking_folio, :secondary, booking:, hotel: booking.hotel,
      hotel_corporate_account: relationship, status: "closed")
    create(:ar_invoice, booking_folio: company_folio, hotel: booking.hotel, hotel_corporate_account: relationship)

    expect {
      described_class.call!(folio: company_folio, issued_by: user, balance: 0)
    }.to raise_error(ArgumentError, /AR invoice/)
  end
end
