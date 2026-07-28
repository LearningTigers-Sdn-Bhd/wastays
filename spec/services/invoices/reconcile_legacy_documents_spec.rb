# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ReconcileLegacyDocuments do
  it "idempotently maps legacy settled and direct-bill documents" do
    settled_folio = create(:booking_folio, status: "closed", invoice_number: 31)
    settled = FolioInvoice.create!(
      hotel: settled_folio.hotel,
      booking_folio: settled_folio,
      invoice_number: settled_folio.invoice_number,
      invoice_year: settled_folio.invoice_year,
      invoice_reference: settled_folio.invoice_reference,
      issued_at: Time.current
    )
    settled.revisions.create!(
      hotel: settled.hotel,
      revision_number: 1,
      document_reference: settled.invoice_reference,
      snapshot: FolioInvoices::Snapshot.call(folio: settled_folio),
      issued_at: settled.issued_at
    )

    relationship = create(:hotel_corporate_account, :direct_bill)
    direct_booking = create(:booking, hotel: relationship.hotel)
    direct_folio = create(:booking_folio, :secondary,
      booking: direct_booking,
      hotel: relationship.hotel,
      hotel_corporate_account: relationship,
      status: "closed")
    direct = ArInvoice.create!(
      hotel: relationship.hotel,
      booking_folio: direct_folio,
      hotel_corporate_account: relationship,
      invoice_number: 41,
      invoice_year: Date.current.year,
      amount: 125,
      paid_amount: 0,
      outstanding_amount: 125,
      currency: direct_folio.currency,
      issued_on: Date.current,
      due_on: Date.current + 30.days,
      metadata: {}
    )

    expect do
      @result = described_class.call
    end.to change(Invoice, :count).by(2)
      .and change(InvoiceRevision, :count).by(2)

    expect(@result.errors).to be_empty
    expect(settled.reload.invoice).to be_kind_settled
    expect(direct.reload.invoice).to be_kind_direct_bill
    expect(direct.invoice.current_revision.snapshot).to include("legacy_generated" => true)

    expect { described_class.call }.not_to change(Invoice, :count)
  end
end
