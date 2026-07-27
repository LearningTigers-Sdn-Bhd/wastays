# frozen_string_literal: true

require "rails_helper"
require "csv"
require "pdf/reader"
require "stringio"

RSpec.describe Reports::Bookings::GenerateFolioLedger do
  let(:hotel) { create(:hotel, hotel_prefix: "LED") }
  let(:booking) { create(:booking, hotel: hotel, confirmation_token: "BK-LEDGER", guest_name: "Ledger Guest", currency: "MYR") }
  let!(:booking_room) { create(:booking_room, booking: booking, room_number: "204") }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel, folio_number: 123, invoice_number: 456, status: "open") }
  let(:code) { create(:transaction_code, hotel: hotel, code: "RM-ACC", name: "Room / Accommodation", kind: "charge", category: "accommodation") }

  before do
    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: code,
      transaction_type: "charge",
      category: "accommodation",
      amount: 150,
      currency: "MYR",
      description: "Room Charge",
      posting_date: Date.new(2026, 6, 18))
  end

  it "generates current folio ledger rows as CSV" do
    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "cash",
      amount: 50,
      currency: "MYR",
      description: "Cash Payment",
      posting_date: Date.new(2026, 6, 19),
      metadata: { "payment_source" => "cash", "receipt_reference" => "RCP-000821" })

    rows = CSV.parse(described_class.new(booking: booking).generate_csv, headers: true)

    expect(rows.size).to eq(2)
    expect(rows.headers).to eq([
      "Folio Account Reference", "Folio Reference", "Booking Ref", "Guest Name", "Room No / Type", "Stay Dates", "Folio Status", "Window", "Currency",
      "Code", "Posting Date", "Description", "Reference", "Source", "Debit", "Credit", "Balance"
    ])
    expect(rows.first.to_h).to include(
      "Folio Account Reference" => "LED-30000123",
      "Folio Reference" => "LED-30000123/1",
      "Booking Ref" => "BK-LEDGER",
      "Guest Name" => "Ledger Guest",
      "Room No / Type" => a_string_starting_with("204 / Deluxe"),
      "Folio Status" => "Open",
      "Window" => "—",
      "Currency" => "MYR",
      "Code" => "RM-ACC",
      "Posting Date" => "2026-06-18",
      "Description" => "Room Charge",
      "Reference" => "",
      "Source" => "Staff",
      "Debit" => "150.00",
      "Credit" => "0.00",
      "Balance" => "150.00"
    )
    expect(rows[1].to_h).to include(
      "Code" => "CASH",
      "Posting Date" => "2026-06-19",
      "Description" => "Payment - Cash",
      "Reference" => "Receipt RCP-000821",
      "Source" => "Staff",
      "Debit" => "0.00",
      "Credit" => "50.00",
      "Balance" => "100.00"
    )
  end

  it "does not include another booking folio transactions" do
    other_booking = create(:booking, hotel: hotel)
    other_folio = create(:booking_folio, booking: other_booking, hotel: hotel)
    create(:folio_transaction, booking_folio: other_folio, amount: 999, description: "Other Booking Charge")

    csv = described_class.new(booking: booking).generate_csv

    expect(csv).to include("Room Charge")
    expect(csv).not_to include("Other Booking Charge")
  end

  it "generates current folio ledger rows as PDF" do
    booking.update!(guest_name: "Ledger & Guest")

    create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "cash",
      amount: 150,
      currency: "MYR",
      description: "Cash Payment",
      posting_date: Date.new(2026, 6, 18),
      metadata: { "payment_source" => "cash", "receipt_reference" => "RCP<&821>" })

    pdf = nil
    reader = nil
    text = nil
    travel_to Time.zone.local(2026, 6, 22, 14, 35, 0) do
      pdf = described_class.new(booking: booking, printed_by: "Platform Admin").generate_pdf
      reader = PDF::Reader.new(StringIO.new(pdf))
      text = reader.pages.map(&:text).join("\n")
    end

    expect(pdf.dup.force_encoding("BINARY")[0, 5]).to eq("%PDF-")
    expect(reader.info[:Title]).to eq("Folio Ledger - LED-30000123/1")
    expect(text).to include("Folio Ledger")
    expect(text).to include("LED-30000123")
    expect(text).to include("BK-LEDGER")
    expect(text).to include("Ledger & Guest")
    expect(text).to include("Room Charge")
    expect(text).to include("FOLIO TOTAL")
    expect(text).to include("Debit")
    expect(text).to include("Credit")
    expect(text).to include("Balance")
    expect(text).to include("Payment - Cash")
    expect(text).to include("Receipt RCP<&821>")
    expect(text).to include("150.00")
    expect(text).to include("0.00")
    expect(text).to include("Printed at 22 Jun 2026 14:35 by Platform Admin")
    expect(text).to include("Page 1 of")
  end

  it "credits negative charge amounts when building debit and credit values" do
    report = described_class.new(booking: booking)
    transaction = instance_double(FolioTransaction, amount: -25.to_d, transaction_type: "charge")

    debit, credit = report.send(:debit_credit_for, transaction)

    expect(debit).to eq(0.to_d)
    expect(credit).to eq(25.to_d)
  end
end
