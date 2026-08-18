# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::Bookings::GenerateFolioRecords do
  subject(:records) { described_class.new(folio: folio, printed_by: "F. Suhaila").call }

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
      reservation_number: 451,
      guest_registration_number: 77,
      check_in: Time.zone.local(2026, 12, 17, 14, 0, 0),
      check_out: Time.zone.local(2026, 12, 19, 12, 0, 0),
      currency: "MYR"
    )
  end
  let!(:booking_room) do
    create(
      :booking_room,
      booking: booking,
      room_number: "412",
      room_type_snapshot: { "name" => "Deluxe King" }
    )
  end
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel, folio_number: 451, invoice_number: 98231, status: "closed") }
  let(:room_code) { create(:transaction_code, hotel: hotel, code: "RM-ACC", name: "Room / Accommodation", kind: "charge", category: "accommodation") }
  let(:service_code) { create(:transaction_code, hotel: hotel, code: "SVC-CHG", name: "Service charge", kind: "charge", category: "tax") }
  let(:sst_code) { create(:transaction_code, hotel: hotel, code: "SST", name: "SST - Room", kind: "charge", category: "tax") }
  let(:tourism_code) { create(:transaction_code, hotel: hotel, code: "TTX-FRN", name: "Tourism Tax - Foreign Guest", kind: "charge", category: "tax") }
  let(:fb_code) { create(:transaction_code, hotel: hotel, code: "FB-REST", name: "Restaurant", kind: "charge", category: "fb") }
  let(:payment_code) { create(:transaction_code, hotel: hotel, code: "PAY-CARD", name: "Card Terminal", kind: "payment", category: "booking_payment") }

  before do
    room_charge = create(:folio_transaction,
      booking_folio: folio,
      transaction_code: room_code,
      transaction_type: "charge",
      category: "accommodation",
      amount: 250,
      description: "Room Charge - Deluxe King",
      posting_date: Date.new(2026, 12, 17))

    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: service_code,
      transaction_type: "charge",
      category: "tax",
      amount: 25,
      description: "Tax: Service Charge 10% for Room Charge - Deluxe King",
      posting_date: Date.new(2026, 12, 17),
      metadata: {
        parent_folio_transaction_id: room_charge.id,
        tax_line: {
          name: "Service Charge 10%",
          type: "service_charge",
          transaction_code_code: "SVC-CHG"
        }
      })

    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: sst_code,
      transaction_type: "charge",
      category: "tax",
      amount: 20,
      description: "Tax: SST 8% for Room Charge - Deluxe King",
      posting_date: Date.new(2026, 12, 17),
      metadata: {
        parent_folio_transaction_id: room_charge.id,
        tax_line: {
          name: "SST 8%",
          type: "sst",
          transaction_code_code: "SST"
        }
      })

    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: tourism_code,
      transaction_type: "charge",
      category: "tax",
      amount: 10,
      description: "Tax: Tourism Tax - Foreign Guest for Room Charge - Deluxe King",
      posting_date: Date.new(2026, 12, 17),
      metadata: {
        parent_folio_transaction_id: room_charge.id,
        tax_line: {
          name: "Tourism Tax - Foreign Guest",
          type: "tourism_tax",
          transaction_code_code: "TTX-FRN"
        }
      })

    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: fb_code,
      transaction_type: "charge",
      category: "fb",
      amount: 85.50,
      description: "Restaurant - Dinner",
      posting_date: Date.new(2026, 12, 17))

    create(:folio_transaction,
      booking_folio: folio,
      transaction_code: payment_code,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 390.50,
      description: "Card payment",
      posting_date: Date.new(2026, 12, 19),
      metadata: {
        payment_source: "card",
        source_references: { card_reference: "552190" }
      })

    Invoices::Finalize.call!(folio:, issued_by: nil, balance: 0)
  end

  it "builds the parties the document bills, issues and covers" do
    expect(records.document_kind).to eq("Folio invoice")
    expect(records.invoice_number).to eq("ABC-26798231")

    # The masthead is the hotel as the invoice was issued, not as it is named today.
    expect(records.pdf_hotel.name).to eq("Hotel ABC Resort")
    # The three parts go over separately; the frame is what joins them.
    expect(records.pdf_hotel).to have_attributes(
      address: "Jalan Pantai Cenang", city: "Langkawi", country: "Malaysia"
    )
    expect(records.hotel_contact_line).to eq("Fixed line: - · Phone: +60 12-345 6789 · Email: frontdesk@example.com")

    expect(records.bill_to_entries).to include([ "Guest", "John Doe" ], [ "Country", "Foreign Tourist" ])
    expect(records.invoice_detail_entries).to include([ "Folio no.", folio.folio_reference_display ])
    # The folio number already carries the account reference, so the invoice prints one.
    expect(records.invoice_detail_entries.map(&:first)).not_to include("Account ref")
    expect(records.stay_detail_entries).to include([ "Confirm no.", "BK-778291" ], [ "Room / type", "412 / Deluxe King" ])
  end

  it "reaches the hotel as it can be reached now, not as at the time it billed" do
    hotel.update!(fixed_line_number: "04-955 1200", contact_phone: "+60 19-000 1122", contact_email: nil)

    expect(described_class.new(folio: folio.reload).call.hotel_contact_line).to eq(
      "Fixed line: 04-955 1200 · Phone: +60 19-000 1122 · Email: -"
    )
  end

  it "shows generated tax and charge rows separately with source-derived codes" do
    rows = records.transaction_rows

    expect(rows.map(&:code)).to match_array([ "RM-ACC", "RM-ACC_SVC-CHG", "RM-ACC_SST", "RM-ACC_TTX-FRN", "FB-REST", "PAY-CARD" ])

    room_row = rows.find { |r| r.code == "RM-ACC" }
    svc_row = rows.find { |r| r.code == "RM-ACC_SVC-CHG" }
    sst_row = rows.find { |r| r.code == "RM-ACC_SST" }
    ttx_row = rows.find { |r| r.code == "RM-ACC_TTX-FRN" }

    expect(room_row).to have_attributes(
      description: "Room Charge - Deluxe King",
      net: 250.to_d,
      charges: nil,
      gross: 250.to_d,
      secondary_description: nil
    )
    expect(svc_row).to have_attributes(description: "Service Charge 10%", charges: 25.to_d, gross: 25.to_d)
    expect(sst_row).to have_attributes(description: "SST 8%", charges: 20.to_d, gross: 20.to_d)
    expect(ttx_row).to have_attributes(description: "Tourism Tax - Foreign Guest", charges: 10.to_d, gross: 10.to_d)
  end

  it "uses user-facing payment labels and safe references" do
    payment = records.transaction_rows.last

    expect(payment.description).to eq("Payment - Card Terminal")
    expect(payment.secondary_description).to eq("Card Ref: 552190")
    expect(payment.gross).to eq(390.50.to_d)
    expect(payment.code).to eq("PAY-CARD")
  end

  it "formats invoice amount cells without repeating currency" do
    expect(records.amount(504)).to eq("504.00")
    expect(records.credit_amount(504)).to eq("(504.00)")
  end

  it "builds summary rows that reconcile to the displayed transaction rows" do
    summary = records.summary_rows.index_by(&:label)

    expect(summary.fetch("Room revenue, net").amount).to eq(250.to_d)
    expect(summary.fetch("F&B and other revenue, net").amount).to eq(85.50.to_d)
    expect(summary.fetch("Service charge").amount).to eq(25.to_d)
    expect(summary.fetch("SST 8% on rooms").amount).to eq(20.to_d)
    expect(summary.fetch("Tourism tax").amount).to eq(10.to_d)
    expect(summary.fetch("Balance settled").amount).to eq(0.to_d)

    # The two totals belong to the tables that produce them, so the summary states the
    # decomposition and the bottom line without restating either.
    expect(summary.keys).not_to include("Total due", "Total payments")
    expect(records.total_due).to eq(390.50.to_d)
    expect(records.total_payments).to eq(390.50.to_d)
    expect(summary.values.filter_map(&:amount).sum - records.balance).to eq(records.total_due)
  end

  it "badges the document with what its own figures say" do
    expect(records.status_badge).to eq(label: "Settled", variant: :positive)
  end

  it "sets the balance apart from the decomposition above it" do
    labels = records.summary_rows.map(&:label)
    variants = records.summary_rows.map(&:variant)

    expect(labels.last).to eq("Balance settled")
    expect(variants[-2]).to eq(:spacer)
    expect(records.summary_rows[-2].amount).to be_nil
  end

  it "counts a parentless room tax against rooms, on the basis the tax line records" do
    # How a room tax is actually posted: no parent_folio_transaction_id, and the charge it
    # belongs to identified only by a source_transaction_code_id. The code lookup behind
    # that is empty once the invoice renders from its snapshot, so the basis is all the
    # document has to go on.
    other_booking = create(:booking, hotel: hotel, currency: "MYR")
    other_folio = create(:booking_folio, booking: other_booking, hotel: hotel, status: "closed")
    create(:folio_transaction,
      booking_folio: other_folio, transaction_code: room_code, transaction_type: "charge",
      category: "accommodation", amount: 1000, description: "Room Charge",
      posting_date: Date.new(2026, 12, 17))
    create(:folio_transaction,
      booking_folio: other_folio, transaction_code: sst_code, transaction_type: "charge",
      category: "tax", amount: 80, description: "Tax: SST 8% - 2026-12-17",
      posting_date: Date.new(2026, 12, 17),
      metadata: { tax_line: { name: "SST 8%", type: "sst", basis: "nightly_room_charge", source_transaction_code_id: 99 } })
    create(:folio_transaction,
      booking_folio: other_folio, transaction_code: payment_code, transaction_type: "payment",
      category: "booking_payment", amount: 1080, description: "Card payment",
      posting_date: Date.new(2026, 12, 17), metadata: { payment_source: "card" })
    Invoices::Finalize.call!(folio: other_folio, issued_by: nil, balance: 0)

    summary = described_class.new(folio: other_folio.reload).call.summary_rows.index_by(&:label)

    expect(summary.fetch("SST 8% on rooms").amount).to eq(80.to_d)
    expect(summary.keys).not_to include("SST 6% on F&B and other")
  end

  it "keeps payment references off the charge rows" do
    charge = records.charge_rows.find { |row| row.code == "FB-REST" }

    expect(charge.secondary_description).to be_nil
    expect(records.charge_rows.map(&:secondary_description).compact).to be_empty
  end

  it "splits what the stay cost from what was paid against it" do
    expect(records.charge_rows.map(&:code)).to match_array(
      [ "RM-ACC", "RM-ACC_SVC-CHG", "RM-ACC_SST", "RM-ACC_TTX-FRN", "FB-REST" ]
    )
    expect(records.payment_rows.map(&:code)).to eq([ "PAY-CARD" ])
    expect(records.charge_rows + records.payment_rows).to match_array(records.transaction_rows)
  end

  it "names the balance settled and keeps it out of the alert colour" do
    balance = records.summary_rows.last

    expect(balance.label).to eq("Balance settled")
    expect(balance.variant).to eq(:subtotal)
  end

  it "shows the notes that apply to this folio" do
    expect(records.notes).to include("SST is not applied on top of Tourism Tax.")
    expect(records.notes).to include("Service Charge is shown separately from government tax.")
  end

  context "when the issuer publishes a landline" do
    let(:hotel) { super().tap { |record| record.update!(fixed_line_number: "04-955 1200") } }

    it "names every way of reaching the issuer, in one line" do
      expect(records.hotel_contact_line).to eq(
        "Fixed line: 04-955 1200 · Phone: +60 12-345 6789 · Email: frontdesk@example.com"
      )
    end
  end

  it "dashes the tax registrations an issuer does not hold rather than dropping them" do
    expect(records.document_kind).to eq("Folio invoice")
    expect(records.hotel_identifier_line).to eq("TIN: - · SST: - · Tourism Tax: -")
  end

  context "when the issuer holds some of the registrations but not all" do
    let(:hotel) { super().tap { |record| record.update!(sst_registration_number: "W10-1808-32000012") } }

    it "dashes only the ones that are missing" do
      expect(records.hotel_identifier_line).to eq("TIN: - · SST: W10-1808-32000012 · Tourism Tax: -")
    end
  end

  context "when the issuer was registered for tax at the time it billed" do
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

    it "calls the document a tax invoice and prints how the issuer is registered" do
      expect(records.document_kind).to eq("Tax invoice · Folio")
      expect(records.hotel_identifier_line).to eq(
        "TIN: C21836402070 · SST: W10-1808-32000012 · Tourism Tax: T-0402-1234-5678"
      )
    end

    it "keeps the registrations it was issued under after the hotel changes them" do
      records_at_issue = records

      hotel.update!(sst_enabled: false, sst_registration_number: "W10-9999-99999999", tin: nil)

      expect(records_at_issue.document_kind).to eq("Tax invoice · Folio")
      expect(records_at_issue.hotel_identifier_line).to include("W10-1808-32000012", "C21836402070")
    end
  end

  context "when the invoice has been reissued" do
    before do
      folio.invoice.update!(state: "under_correction")
      Invoices::Finalize.call!(folio: folio.reload, issued_by: nil, balance: 0)
    end

    it "says on its face that it is a revision and what it supersedes" do
      reissued = described_class.new(folio: folio.reload).call

      expect(reissued.invoice_number).to eq("ABC-26798231-2")
      expect(reissued.invoice_detail_entries.to_h).to include("Revision" => "2")
      expect(reissued.notes).to include("Revision 2 of this invoice; it supersedes ABC-26798231.")
    end
  end

  it "dates the invoice by when it was issued, not by when it was printed" do
    entries = records.invoice_detail_entries.to_h
    issued_on = folio.reload.invoice.issued_on

    expect(entries["Issue date"]).to eq(HotelPortal::Reports::Exports::PdfTheme.format_date(issued_on))
    expect(entries.keys).not_to include("Generated")
  end

  it "leaves the payment reference on its own row rather than repeating it as a note" do
    payment = records.transaction_rows.last

    expect(payment.secondary_description).to eq("Card Ref: 552190")
    expect(records.notes.join(" ")).not_to include("Card Ref: 552190")
    expect(records.notes.join(" ")).not_to include("Currency:")
  end

  it "omits the room revenue line on a folio that posted no room charge" do
    other_booking = create(:booking, hotel: hotel, currency: "MYR")
    other_folio = create(:booking_folio, booking: other_booking, hotel: hotel, status: "closed")
    create(:folio_transaction,
      booking_folio: other_folio,
      transaction_code: fb_code,
      transaction_type: "charge",
      category: "fb",
      amount: 40,
      description: "Restaurant - Dinner",
      posting_date: Date.new(2026, 12, 18))
    create(:folio_transaction,
      booking_folio: other_folio,
      transaction_code: payment_code,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 40,
      description: "Card payment",
      posting_date: Date.new(2026, 12, 18))
    Invoices::Finalize.call!(folio: other_folio, issued_by: nil, balance: 0)

    labels = described_class.new(folio: other_folio.reload).call.summary_rows.map(&:label)

    expect(labels).not_to include("Room revenue, net")
    expect(labels).to include("F&B and other revenue, net")
  end

  it "hides fully reversed transaction noise" do
    original = create(:folio_transaction,
      booking_folio: folio,
      transaction_code: room_code,
      transaction_type: "charge",
      category: "accommodation",
      amount: 99,
      description: "Wrong room charge",
      posting_date: Date.new(2026, 12, 17))
    reversal = create(:folio_transaction,
      booking_folio: folio,
      transaction_type: "adjustment",
      category: "correction",
      amount: -99,
      description: "Reversal of transaction",
      posting_date: Date.new(2026, 12, 17),
      reversal_of_transaction: original)
    original.update!(voided_by_transaction: reversal)

    fresh_records = described_class.new(folio: folio).call

    expect(fresh_records.transaction_rows.map(&:description)).not_to include("Wrong room charge", "Reversal of transaction")
    expect(fresh_records.total_due).to eq(390.50.to_d)
  end

  it "rejects folios without an issued invoice" do
    unissued_folio = create(:booking_folio, booking: create(:booking, hotel: hotel), hotel: hotel, status: "closed")

    expect { described_class.new(folio: unissued_folio).call }.to raise_error(described_class::UnavailableError)
  end

  it "rejects open folios" do
    open_booking = create(:booking, hotel: hotel)
    create(:booking_folio, booking: open_booking, hotel: hotel, folio_number: 999, status: "open")

    expect { described_class.new(folio: open_booking.booking_folio).call }.to raise_error(described_class::UnavailableError)
  end
end
