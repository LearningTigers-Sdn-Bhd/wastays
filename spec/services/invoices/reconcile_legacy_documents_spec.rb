# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ReconcileLegacyDocuments do
  it "idempotently maps unlinked receivables onto direct-bill documents" do
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
    end.to change(Invoice, :count).by(1)
      .and change(InvoiceRevision, :count).by(1)

    expect(@result.errors).to be_empty
    expect(@result.direct_bill_mapped).to eq(1)
    expect(direct.reload.invoice).to be_kind_direct_bill
    expect(direct.invoice.current_revision.snapshot).to include("legacy_generated" => true)

    expect { described_class.call }.not_to change(Invoice, :count)
  end
end
