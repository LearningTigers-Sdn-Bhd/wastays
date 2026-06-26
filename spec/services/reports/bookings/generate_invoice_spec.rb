# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe ::Reports::Bookings::GenerateInvoice do
  let(:hotel) do
    create(:hotel,
      name: "Hotel ABC Resort",
      hotel_prefix: "ABC",
      address: "Jalan Pantai Cenang",
      city: "Langkawi",
      country: "Malaysia",
      contact_phone: "+60 12-345 6789",
      contact_email: "frontdesk@example.com")
  end
  let(:booking) do
    create(
      :booking,
      hotel: hotel,
      guest_name: "John Doe",
      guest_country: "Foreign Tourist",
      confirmation_token: "BK-778291",
      check_in: Time.zone.local(2026, 12, 17, 14, 0, 0),
      check_out: Time.zone.local(2026, 12, 19, 12, 0, 0),
      currency: "MYR"
    )
  end
  let!(:booking_room) do
    create(:booking_room, booking: booking, room_number: "412", room_type_snapshot: { "name" => "Deluxe King" })
  end
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel, folio_number: 451, invoice_number: 98231, status: "closed") }

  before do
    room_code = create(:transaction_code, hotel: hotel, code: "RM-ACC", name: "Room / Accommodation", kind: "charge", category: "accommodation")
    sst_code = create(:transaction_code, hotel: hotel, code: "SST", name: "SST - Room", kind: "charge", category: "tax")
    payment_code = create(:transaction_code, hotel: hotel, code: "PAY-CASH", name: "Cash", kind: "payment", category: "cash")
    refund_code = create(:transaction_code, hotel: hotel, code: "RFND-PDF", name: "Refund", kind: "payment", category: "refund")

    room_charge = create(:folio_transaction,
      booking_folio: folio,
      transaction_code: room_code,
      transaction_type: "charge",
      category: "accommodation",
      amount: 100,
      description: "Room Charge - Deluxe King",
      posting_date: Date.new(2026, 12, 17),
      metadata: { night_audit_id: 999, catch_up_key: "hidden-key" })

    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: sst_code,
      transaction_type: "charge",
      category: "tax",
      amount: 8,
      description: "Tax: SST 8% for Room Charge - Deluxe King",
      posting_date: Date.new(2026, 12, 17),
      metadata: {
        parent_folio_transaction_id: room_charge.id,
        tax_line: {
          name: "SST 8%",
          type: "sst",
          transaction_code_code: "SST"
        },
        posting_source: "night_audit"
      })

    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: payment_code,
      transaction_type: "payment",
      category: "cash",
      amount: 108,
      description: "Cash payment",
      posting_date: Date.new(2026, 12, 19),
      metadata: {
        payment_source: "cash",
        source_references: { receipt_reference: "RCP-000821" }
      })

    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: refund_code,
      transaction_type: "payment",
      category: "refund",
      amount: -20,
      description: "Refund",
      posting_date: Date.new(2026, 12, 19),
      metadata: {
        refund_request_id: 152
      })
  end

  describe "#generate" do
    it "renders the redesigned guest folio invoice text" do
      travel_to Time.zone.local(2026, 6, 22, 14, 35, 0) do
        text = pdf_text(described_class.new(booking: booking, printed_by: "F. Suhaila").generate)

        expect(text).to include("GUEST FOLIO / INVOICE")
        expect(text).to include("HOTEL INFORMATION")
        expect(text).to include("Hotel Name")
        expect(text).to include("Hotel ABC Resort")
        expect(text).to include("Jalan Pantai Cenang, Langkawi, Malaysia")
        expect(text).to include("+60 12-345 6789")
        expect(text).to include("frontdesk@example.com")
        expect(text).to include("GUEST / FOLIO DETAILS")
        expect(text).to include("BOOKING / STAY DETAILS")
        expect(text).to include("Guest Name")
        expect(text).to include("John Doe")
        expect(text).to include("Invoice No")
        expect(text).to include("Date")
        expect(text).to include("Code")
        expect(text).to include("Description")
        expect(text).to include("Qty")
        expect(text).to include("Net (MYR)")
        expect(text).to include("Charges (MYR)")
        expect(text).to include("Gross (MYR)")
        expect(text).to include("Room Charge - Deluxe King")
        expect(text).to include("RM-ACC")
        expect(text).to include("RM-ACC_SST")
        expect(text).to include("SST 8%")
        expect(text).to include("Payment - Cash")
        expect(text).to include("Receipt: RCP-000821")
        expect(text).to include("Refund - Refund")
        expect(text).to include("-20.00")
        expect(text).not_to include("(20.00)")
        expect(text).to include("SUMMARY (MYR)")
        expect(text).to include("Room Revenue, net")
        expect(text).to include("Total Due")
        expect(text).to include("Balance")
        expect(text).to include("Transaction Code Legend")
        expect(text).to include("Guest Signature")
        expect(text).to include("Authorised Signature")
        expect(text).to include("Printed at 22 Jun 2026 14:35 by F. Suhaila")
        expect(text).to include("Page 1 of")
        expect(text).not_to include("Printed by: F. Suhaila")
        expect(text).not_to include("Guest Name:")
        expect(text).not_to include("MYR 100.00")
      end
    end

    it "does not expose internal folio metadata" do
      text = pdf_text(described_class.new(booking: booking).generate)

      expect(text).not_to include("night_audit_id")
      expect(text).not_to include("catch_up_key")
      expect(text).not_to include("posting_source")
      expect(text).not_to include("booking_payment")
    end

    it "rejects open folios" do
      open_booking = create(:booking, hotel: hotel)
      create(:booking_folio, booking: open_booking, hotel: hotel, status: "open")

      expect { described_class.new(booking: open_booking).generate }
        .to raise_error(::Reports::Bookings::GenerateFolioRecords::UnavailableError)
    end
  end

  def pdf_text(pdf)
    PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
  end
end
