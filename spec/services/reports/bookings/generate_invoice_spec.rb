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

    Invoices::Finalize.call!(folio:, issued_by: nil, balance: 0)
  end

  describe "#generate" do
    it "renders the redesigned guest folio invoice text" do
      with_frozen_time Time.zone.local(2026, 6, 22, 14, 35, 0) do
        text = pdf_text(described_class.new(folio: folio, printed_by: "F. Suhaila").generate)

        # The number is the title; the eyebrow above it says what kind of invoice it is,
        # and the hotel it bills for is the masthead.
        expect(text).to include("FOLIO INVOICE")
        expect(text).to include("ABC-26798231")
        expect(text).to include("Hotel ABC Resort")
        expect(text).to include("Jalan Pantai Cenang, Langkawi, Malaysia")
        expect(text).to include("+60 12-345 6789")
        expect(text).to include("frontdesk@example.com")
        expect(text).to include("BILL TO")
        expect(text).to include("INVOICE DETAILS")
        expect(text).to include("STAY DETAILS")
        expect(text).to include("John Doe")
        expect(text).to include("Foreign Tourist")
        expect(text).to include("Issued by", "F. Suhaila")
        expect(text).to include("Folio no.", folio.folio_reference_display)
        # The invoice is dated by its issue date; when this copy was printed sits apart.
        expect(text).to include("Issue date")
        expect(text).to include("Printed")
        expect(text).to include("Confirm no.", "BK-778291")
        expect(text).to include("412 / Deluxe King")
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
        expect(text).to include("Summary (MYR)")
        expect(text).to include("Room Revenue, net")
        expect(text).to include("Total Due")
        expect(text).to include("Balance")
        # The code column is on the invoice, so the legend that decoded it is not.
        expect(text).not_to include("Transaction Code Legend")
        expect(text).to include("GUEST SIGNATURE")
        expect(text).to include("AUTHORISED SIGNATURE")
        # The shared footer replaces the printed-at line; who printed it is a party now.
        expect(text).to include("Generated by")
        expect(text).not_to include("Confidential")
        expect(text).to include("Page 1 of")
        expect(text).not_to include("Printed by: F. Suhaila")
        expect(text).not_to include("Guest Name:")
        expect(text).not_to include("MYR 100.00")
      end
    end

    context "when the issuer is registered for tax" do
      let(:hotel) do
        super().tap do |record|
          record.update!(
            sst_enabled: true,
            tin: "C21836402070",
            sst_registration_number: "W10-1808-32000012",
            tourism_tax_registration_number: "T-0402-1234-5678"
          )
        end
      end

      it "names the document a tax invoice and registers the issuer under the masthead" do
        text = pdf_text(described_class.new(folio: folio, printed_by: "F. Suhaila").generate)

        expect(text).to include("TAX INVOICE")
        expect(text).to include("TIN: C21836402070")
        expect(text).to include("SST: W10-1808-32000012")
        expect(text).to include("Tourism Tax: T-0402-1234-5678")
      end
    end

    it "does not expose internal folio metadata" do
      text = pdf_text(described_class.new(folio: folio).generate)

      expect(text).not_to include("night_audit_id")
      expect(text).not_to include("catch_up_key")
      expect(text).not_to include("posting_source")
      expect(text).not_to include("booking_payment")
    end

    it "rejects open folios" do
      open_booking = create(:booking, hotel: hotel)
      open_folio = create(:booking_folio, booking: open_booking, hotel: hotel, status: "open")

      expect { described_class.new(folio: open_folio).generate }
        .to raise_error(::Reports::Bookings::GenerateFolioRecords::UnavailableError)
    end

    it "renders historical values from the finalized revision snapshot" do
      original_name = hotel.name
      hotel.update!(name: "Renamed Hotel")

      text = pdf_text(described_class.new(folio: folio).generate)

      expect(text).to include(original_name)
      expect(text).not_to include("Renamed Hotel")
    end

    it "renders a requested historical revision separately from the current revision" do
      invoice = folio.invoice
      invoice.update!(state: "under_correction")
      folio.update_column(:status, "open")
      create(:folio_transaction,
        booking_folio: folio,
        transaction_type: "adjustment",
        category: "correction",
        amount: -20,
        description: "Revision two correction")
      folio.update_column(:status, "closed")
      Invoices::Finalize.call!(folio:, issued_by: nil, balance: 0)

      original_text = pdf_text(described_class.new(folio:, revision_number: 1).generate)
      current_text = pdf_text(described_class.new(folio:).generate)

      expect(original_text).not_to include("Revision two correction")
      expect(current_text).to include("Revision two correction")
      expect(current_text).to include("#{invoice.invoice_reference}-2")
    end

    it "marks a legacy invoice as a reconstruction" do
      legacy_folio = create(:booking_folio, booking:, hotel:, status: "closed", invoice_number: 98_232, is_primary: false)
      create(:folio_transaction, booking_folio: legacy_folio, amount: 50, description: "Legacy charge")
      create(:invoice, booking_folio: legacy_folio, legacy: true)

      text = pdf_text(described_class.new(folio: legacy_folio).generate)

      expect(text).to include("RECONSTRUCTED FROM RECORDS")
      expect(text).to include("original issue-time snapshot was not available")
    end

    it "uses the issuance-time hotel time zone for historical stay timestamps" do
      expected_arrival = folio.invoice.current_revision.snapshot.dig("booking", "check_in")
      original_zone = folio.invoice.current_revision.snapshot.dig("hotel", "time_zone")
      hotel.update!(time_zone: "Pacific Time (US & Canada)")

      records = Reports::Bookings::GenerateFolioRecords.new(folio:).call

      expect(records.stay_detail_entries).to include(
        [ "Arrival", HotelPortal::Reports::Exports::PdfTheme.format_time(Time.zone.parse(expected_arrival), original_zone) ]
      )
    end

    it "uses snapshotted corporate payer and immediate-payment references" do
      relationship = create(
        :hotel_corporate_account,
        hotel:,
        corporate_account: create(:account, :corporate, name: "Acme Events"),
        account_type: "company"
      )
      party = create(
        :booking_billing_party,
        :company,
        booking:,
        hotel:,
        hotel_corporate_account: relationship,
        account_type: "company"
      )
      terms = create(
        :booking_billing_terms,
        booking_billing_party: party,
        purchase_order_reference: "PO-CASH-42",
        authorization_reference: "AUTH-CASH-9"
      )
      corporate_folio = create(
        :booking_folio,
        :secondary,
        booking:,
        hotel:,
        booking_billing_party: party,
        hotel_corporate_account: relationship,
        status: "closed"
      )
      Invoices::Finalize.call!(folio: corporate_folio, issued_by: nil, balance: 0)
      relationship.corporate_account.update!(name: "Renamed Events")
      terms.update!(purchase_order_reference: "PO-CHANGED", authorization_reference: "AUTH-CHANGED")

      text = pdf_text(described_class.new(folio: corporate_folio).generate)

      expect(text).to include("FOLIO INVOICE", "BILL TO (PAYER)", "Acme Events", "Company", "PO-CASH-42", "AUTH-CASH-9")
      expect(text).not_to include("Renamed Events", "PO-CHANGED", "AUTH-CHANGED")
    end
  end

  def pdf_text(pdf)
    PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
  end
end
