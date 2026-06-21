# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::GuestFolioPresenter do
  subject(:presenter) { described_class.new(booking: booking, printed_by: "F. Suhaila") }

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
  let(:service_code) { create(:transaction_code, hotel: hotel, code: "SVC-CHG", name: "Service Charge", kind: "charge", category: "tax") }
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
  end

  it "builds guest and folio metadata for the document" do
    expect(presenter.document_title).to eq("GUEST FOLIO / INVOICE")
    expect(presenter.hotel_info_rows).to include(
      [ "Hotel Name", "Hotel ABC Resort" ],
      [ "Address", "Jalan Pantai Cenang, Langkawi, Malaysia" ],
      [ "Contact", "+60 12-345 6789 · frontdesk@example.com" ]
    )
    expect(presenter.guest_folio_detail_rows).to include([ "Guest Name", "John Doe" ])
    expect(presenter.guest_folio_detail_rows).to include([ "Nationality", "Foreign Tourist" ])
    expect(presenter.guest_folio_detail_rows).to include([ "Invoice No", "ABC-30098231" ])
    expect(presenter.guest_folio_detail_rows).to include([ "Currency", "MYR" ])
    expect(presenter.booking_stay_detail_rows).to include([ "Room No / Type", "412 / Deluxe King" ])
    expect(presenter.booking_stay_detail_rows).to include([ "Folio No", "ABC-30000451" ])
    expect(presenter.booking_stay_detail_rows).to include([ "Confirm No", "BK-778291" ])
  end

  it "omits missing optional hotel information rows" do
    hotel.update!(contact_phone: nil, contact_email: nil)

    expect(described_class.new(booking: booking).hotel_info_rows.map(&:first)).not_to include("Contact")
  end

  it "shows generated tax and charge rows separately with source-derived codes" do
    rows = presenter.transaction_rows

    expect(rows.map(&:code)).to eq([ "RM-ACC", "RM-ACC_SVC-CHG", "RM-ACC_SST", "RM-ACC_TTX-FRN", "FB-REST", "PAY-CARD" ])
    expect(rows[0]).to have_attributes(
      description: "Room Charge - Deluxe King",
      net: 250.to_d,
      charges: nil,
      gross: 250.to_d,
      secondary_description: nil
    )
    expect(rows[1]).to have_attributes(description: "Service Charge 10%", charges: 25.to_d, gross: 25.to_d)
    expect(rows[2]).to have_attributes(description: "SST 8%", charges: 20.to_d, gross: 20.to_d)
    expect(rows[3]).to have_attributes(description: "Tourism Tax - Foreign Guest", charges: 10.to_d, gross: 10.to_d)
  end

  it "uses user-facing payment labels and safe references" do
    payment = presenter.transaction_rows.last

    expect(payment.description).to eq("Payment - Card Terminal")
    expect(payment.secondary_description).to eq("Card Ref: 552190")
    expect(payment.gross).to eq(390.50.to_d)
    expect(payment.code).to eq("PAY-CARD")
  end

  it "formats invoice amount cells without repeating currency" do
    expect(presenter.amount(504)).to eq("504.00")
    expect(presenter.credit_amount(504)).to eq("(504.00)")
    expect(presenter.money(504)).to eq("MYR 504.00")
  end

  it "builds summary rows that reconcile to the displayed transaction rows" do
    summary = presenter.summary_rows.index_by(&:label)

    expect(summary.fetch("Room Revenue, net").amount).to eq(250.to_d)
    expect(summary.fetch("F&B / Other Revenue, net").amount).to eq(85.50.to_d)
    expect(summary.fetch("Service Charge").amount).to eq(25.to_d)
    expect(summary.fetch("SST 8% - Rooms").amount).to eq(20.to_d)
    expect(summary.fetch("Tourism Tax").amount).to eq(10.to_d)
    expect(summary.fetch("Total Due").amount).to eq(390.50.to_d)
    expect(summary.fetch("Total Payments").amount).to eq(390.50.to_d)
    expect(summary.fetch("Balance").amount).to eq(0.to_d)
  end

  it "only shows used legend codes and relevant notes" do
    expect(presenter.legend_rows).to include([ "RM-ACC", "Room / Accommodation" ], [ "RM-ACC_SVC-CHG", "Service Charge 10%" ], [ "PAY-CARD", "Card Terminal" ])
    expect(presenter.legend_rows.map(&:first)).not_to include("UNUSED")
    expect(presenter.notes).to include("SST is not applied on top of Tourism Tax.")
    expect(presenter.notes).to include("Service Charge is shown separately from government tax.")
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

    fresh_presenter = described_class.new(booking: booking)

    expect(fresh_presenter.transaction_rows.map(&:description)).not_to include("Wrong room charge", "Reversal of transaction")
    expect(fresh_presenter.total_due).to eq(390.50.to_d)
  end
end
