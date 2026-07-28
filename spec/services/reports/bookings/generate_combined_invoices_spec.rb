# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe Reports::Bookings::GenerateCombinedInvoices do
  let(:hotel) { create(:hotel, name: "Combined Hotel", hotel_prefix: "PKG") }
  let(:group) { create(:group_booking, hotel:) }
  let(:recipient) { Notifications::InvoiceDelivery::Recipient.new(key: "guest:1", kind: "guest", name: "Same Payer", email: "payer@example.test") }

  it "draws a summary followed by complete invoices with combined numbering" do
    first = finalized_invoice(booking_for("SAME-PAYER", 1), 120)
    second = finalized_invoice(booking_for("SAME-PAYER", 2), 80)

    reader = PDF::Reader.new(StringIO.new(described_class.new(hotel:, invoices: [ first, second ], recipient:, printed_by: "Alex").generate))
    text = reader.pages.map(&:text).join("\n")

    expect(reader.pages.size).to be >= 3
    expect(text).to include("COMBINED INVOICES", first.invoice_reference, second.invoice_reference)
    expect(text.scan("FOLIO INVOICE").size).to eq(2)
    expect(text).to include("Total (MYR)", "200.00", "Page 1 of #{reader.pages.size}")
  end

  it "reconstructs non-zero summary totals for a legacy invoice" do
    legacy_booking = booking_for("legacy@example.test", 1)
    folio = create(:booking_folio, booking: legacy_booking, hotel:, status: "closed")
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", category: "accommodation", amount: 100)
    invoice = create(:folio_invoice, booking_folio: folio, create_revision: false, legacy: true)
    create(:folio_invoice_revision, folio_invoice: invoice, hotel:, snapshot: { legacy_generated: true })

    text = PDF::Reader.new(StringIO.new(described_class.new(hotel:, invoices: [ invoice ], recipient:).generate)).pages.map(&:text).join("\n")
    expect(text).to include("Total (MYR)", "100.00")
  end

  it "totals mixed currencies separately" do
    myr_invoice = finalized_invoice(booking_for("payer@example.test", 1), 120)
    usd_booking = booking_for("payer@example.test", 2)
    usd_booking.update!(currency: "USD")
    usd_invoice = finalized_invoice(usd_booking, 80)

    text = PDF::Reader.new(
      StringIO.new(described_class.new(hotel:, invoices: [ myr_invoice, usd_invoice ], recipient:).generate)
    ).pages.map(&:text).join("\n")

    expect(text).to include("Total (MYR)", "120.00", "Total (USD)", "80.00")
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
