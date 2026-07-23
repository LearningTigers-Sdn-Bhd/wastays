# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::RefundReport do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 1) }
  let(:end_date) { Date.new(2026, 5, 31) }

  it "returns refund-only rows and totals" do
    booking = create(:booking, hotel: hotel, guest_name: "Refund Guest", confirmation_token: "WS-RFD")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    refund_request = create(:refund_request, booking: booking, status: "completed", refund_amount: 80.0, reason: "Guest cancelled")

    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "refund",
      amount: -80.0,
      posting_date: Date.new(2026, 5, 7),
      metadata: { refund_request_id: refund_request.id, refund_source: "bank_transfer", reference: "BNK-123" }
    )
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "cash",
      amount: 80.0,
      posting_date: Date.new(2026, 5, 7)
    )

    report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

    expect(report.totals[:refund_count]).to eq(1)
    expect(report.totals[:total_amount]).to eq(80.to_d)
    expect(report.rows.size).to eq(1)
    expect(report.rows.first[:guest_name]).to eq("Refund Guest")
    expect(report.rows.first[:refund_method]).to eq("Bank transfer")
    expect(report.rows.first[:reference]).to eq("BNK-123")
  end

  it "keeps individual refund rows for the this_year preset" do
    booking = create(:booking, hotel: hotel, guest_name: "Refund Guest", confirmation_token: "WS-RFD")
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "refund", amount: -80, posting_date: Date.new(2026, 5, 7))

    report = described_class.new(
      hotel: hotel,
      start_date: Date.new(2026, 1, 1),
      end_date: Date.new(2026, 12, 31),
      date_preset: "this_year"
    ).call

    expect(report.rows).to contain_exactly(include(
      date: Date.new(2026, 5, 7),
      guest_name: "Refund Guest",
      booking_reference: "WS-RFD",
      refund_amount: 80.to_d
    ))
  end
end
