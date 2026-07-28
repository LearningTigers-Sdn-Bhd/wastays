# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260728102000_create_folio_invoices_and_revisions")

RSpec.describe CreateFolioInvoicesAndRevisions do
  it "backfills legacy state, scopes references by hotel, and excludes AR-backed duplicates" do
    first_hotel = create(:hotel)
    second_hotel = create(:hotel)
    closed = legacy_folio(hotel: first_hotel, status: "closed", number: 501, reference: "LEGACY-SHARED")
    reopened = legacy_folio(hotel: first_hotel, status: "open", number: 502, reference: "LEGACY-OPEN")
    voided = legacy_folio(hotel: first_hotel, status: "voided", number: 503, reference: "LEGACY-VOID")
    other_hotel = legacy_folio(hotel: second_hotel, status: "closed", number: 501, reference: "LEGACY-SHARED")

    relationship = create(:hotel_corporate_account, :direct_bill, hotel: first_hotel)
    direct_bill = create(:booking_folio, :secondary,
      booking: create(:booking, hotel: first_hotel),
      hotel: first_hotel,
      hotel_corporate_account: relationship,
      status: "closed",
      invoice_number: 504,
      invoice_year: 2026,
      invoice_reference: "LEGACY-DIRECT-BILL")
    create(:ar_invoice, booking_folio: direct_bill, hotel: first_hotel, hotel_corporate_account: relationship)

    described_class.new.send(:backfill_existing_invoices!)

    expect(closed.reload.folio_invoice).to be_finalized
    expect(reopened.reload.folio_invoice).to be_under_correction
    expect(voided.reload.folio_invoice).to be_voided
    expect(other_hotel.reload.folio_invoice).to be_finalized
    expect(closed.folio_invoice.current_revision.document_reference).to eq("LEGACY-SHARED")
    expect(other_hotel.folio_invoice.current_revision.document_reference).to eq("LEGACY-SHARED")
    expect(direct_bill.reload.folio_invoice).to be_nil
  end

  def legacy_folio(hotel:, status:, number:, reference:)
    create(:booking_folio,
      booking: create(:booking, hotel:),
      hotel:,
      status:,
      invoice_number: number,
      invoice_year: 2026,
      invoice_reference: reference)
  end
end
