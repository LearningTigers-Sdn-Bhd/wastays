# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::CashierActivityExportTable do
  it "expands guest details for data exports and keeps one PDF column" do
    report = HotelPortal::Reports::CashierSalesReport::Result.new(
      transactions: [], cash_transactions: [], non_cash_transactions: [],
      mode_by_transaction_id: {}, section_by_transaction_id: {},
      non_cash_origin_by_transaction_id: {}, handling_by_transaction_id: {},
      received_by_key_by_transaction_id: {}
    )
    table = described_class.new(report:, visible_columns: %w[guest_details amount])

    expect(table.headers).to eq([ "Guest", "Room", "Amount" ])
    expect(table.pdf_headers).to eq([ "Guest / Room", "Amount" ])
    expect(table.money_indexes).to eq([ 2 ])
  end

  it "exports booking numbers and confirmation codes as separate data columns" do
    hotel = create(:hotel)
    booking = create(:booking, hotel:)
    booking.update_columns(reservation_reference: "RES-2026-0042", confirmation_token: "ABC123")
    folio = create(:booking_folio, booking:, hotel:, invoice_number: 42)
    transaction = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 100)
    report = HotelPortal::Reports::CashierSalesReport::Result.new(
      transactions: [ transaction ], cash_transactions: [ transaction ], non_cash_transactions: [],
      mode_by_transaction_id: { transaction.id => "Cash Payment" },
      section_by_transaction_id: { transaction.id => "Settlement" },
      non_cash_origin_by_transaction_id: {}, handling_by_transaction_id: { transaction.id => "at_desk" },
      received_by_key_by_transaction_id: { transaction.id => "unassigned" }
    )

    table = described_class.new(report:, visible_columns: %w[reservation invoice])

    expect(table.headers).to eq([ "Booking No.", "Confirmation Code", "Invoice" ])
    expect(table.rows).to eq([ [ "RES-2026-0042", "ABC123", folio.invoice_reference ] ])
    expect(table.pdf_rows).to eq([ [ "Booking RES-2026-0042\nConfirmation ABC123", folio.invoice_reference ] ])
  end
end
