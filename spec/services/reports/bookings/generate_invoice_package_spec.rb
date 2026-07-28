# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe Reports::Bookings::GenerateInvoicePackage do
  let(:hotel) { create(:hotel, name: "Package Hotel", hotel_prefix: "PKG") }
  let(:group) { create(:group_booking, hotel:) }

  it "draws a summary followed by complete invoices with package-wide numbering" do
    first = finalized_invoice(booking_for("SAME-PAYER", 1), 120)
    second = finalized_invoice(booking_for("SAME-PAYER", 2), 80)

    reader = PDF::Reader.new(StringIO.new(described_class.new(hotel:, folio_invoice_ids: [ first.id, second.id ], printed_by: "Alex").generate))
    text = reader.pages.map(&:text).join("\n")

    expect(reader.pages.size).to be >= 3
    expect(text).to include("INVOICE PACKAGE", first.invoice_reference, second.invoice_reference)
    expect(text.scan("GUEST FOLIO / INVOICE").size).to eq(2)
    expect(text).to include("Total (MYR)", "200.00", "Page 1 of #{reader.pages.size}")
  end

  it "rejects invoices belonging to different payers" do
    first = finalized_invoice(booking_for("one@example.test", 1), 100)
    second = finalized_invoice(booking_for("two@example.test", 2), 100)

    expect { described_class.new(hotel:, folio_invoice_ids: [ first.id, second.id ]).generate }
      .to raise_error(described_class::InvalidPackageError, /same payer/)
  end

  def booking_for(email, position)
    create(:booking,
      hotel:,
      group_booking: group,
      group_position: position,
      guest_email: email,
      confirmation_token: "PKG-#{position}")
  end

  def finalized_invoice(booking, amount)
    folio = create(:booking_folio, booking:, hotel:, status: "closed")
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount:)
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount:)
    FolioInvoices::Finalize.call!(folio:, issued_by: nil, balance: 0)
  end
end
