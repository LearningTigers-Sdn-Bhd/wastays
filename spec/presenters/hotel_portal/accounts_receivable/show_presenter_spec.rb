# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::AccountsReceivable::ShowPresenter do
  subject(:presenter) { described_class.new(invoice: invoice, hotel: hotel) }

  let(:hotel) { create(:hotel, status: "approved", default_currency: "MYR", time_zone: "Kuala Lumpur") }
  let(:relationship) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      corporate_account: create(:account, :corporate, name: "Northstar Travel"),
      payment_terms_days: 45,
      direct_bill_enabled: true
    )
  end
  let(:booking) { create(:booking, hotel: hotel, confirmation_token: "BK-NORTHSTAR") }
  let(:folio) do
    create(
      :booking_folio,
      :secondary,
      hotel: hotel,
      booking: booking,
      hotel_corporate_account: relationship,
      folio_number: 711
    )
  end
  let(:invoice) do
    create(
      :ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      invoice_number: 84,
      status: "partially_paid",
      amount: 500,
      paid_amount: 125,
      outstanding_amount: 375,
      currency: "MYR",
      issued_on: Date.new(2026, 6, 1),
      due_on: Date.new(2026, 7, 1),
      created_at: Time.utc(2026, 6, 1, 0, 30),
      metadata: {
        booking_id: booking.id,
        corporate_account_name: "Northstar Travel",
        payment_terms_days: 30,
        folio_balance: "500.00",
        direct_bill_closed_at: "2026-06-01T00:15:00Z",
        audit_flags: { imported: true }
      }
    )
  end

  it "formats invoice identity, status, money, dates, terms, and source references" do
    expect(presenter.invoice_label).to eq("AR-84")
    expect(presenter.company_name).to eq("Northstar Travel")
    expect(presenter.status_label).to eq("Partially paid")
    expect(presenter.status_class).to include("bg-amber-50")
    expect(presenter.original_amount_label).to eq("MYR 500.00")
    expect(presenter.paid_amount_label).to eq("MYR 125.00")
    expect(presenter.outstanding_amount_label).to eq("MYR 375.00")
    expect(presenter.booking_reference).to eq("BK-NORTHSTAR")
    expect(presenter.folio_reference).to eq(folio.folio_reference_display)
    expect(presenter.payment_terms_label).to eq("Net 30 days")
    expect(presenter.issued_on_label).to eq("01 Jun 2026")
    expect(presenter.due_on_label).to eq("01 Jul 2026")
    expect(presenter.direct_bill_source_label).to eq("Folio close")
    expect(presenter.created_at_label).to eq("01 Jun 2026, 08:30 AM")
  end

  it "falls back to the relationship payment terms and empty direct-bill source" do
    invoice.update!(metadata: {})

    expect(presenter.payment_terms_label).to eq("Net 45 days")
    expect(presenter.direct_bill_source_label).to eq("—")
    expect(presenter.technical_snapshot_rows).to be_empty
  end

  it "orders allocation rows newest first and formats their values" do
    older_payment = create(
      :ar_payment,
      hotel: hotel,
      hotel_corporate_account: relationship,
      amount: 50,
      currency: "MYR",
      reference_number: "BANK-OLD",
      received_at: Date.new(2026, 6, 5),
      payment_method: "bank_transfer"
    )
    newer_payment = create(
      :ar_payment,
      hotel: hotel,
      hotel_corporate_account: relationship,
      amount: 75,
      currency: "MYR",
      reference_number: "CHQ-NEW",
      received_at: Date.new(2026, 6, 8),
      payment_method: "cheque"
    )
    create(:ar_payment_allocation, ar_payment: older_payment, ar_invoice: invoice, amount: 50)
    create(:ar_payment_allocation, ar_payment: newer_payment, ar_invoice: invoice, amount: 75)

    rows = described_class.new(invoice: invoice.reload, hotel: hotel).allocation_rows

    expect(rows.map(&:reference)).to eq([ "CHQ-NEW", "BANK-OLD" ])
    expect(rows.first).to have_attributes(
      received_on: "08 Jun 2026",
      payment_method: "Cheque",
      allocated_amount: "MYR 75.00"
    )
  end

  it "humanizes snapshot labels and formats IDs, money, timestamps, and nested values" do
    rows = presenter.technical_snapshot_rows.index_by(&:label)

    expect(rows.fetch("Booking").value).to eq(booking.id.to_s)
    expect(rows.fetch("Payment Terms Days").value).to eq("30 days")
    expect(rows.fetch("Folio Balance").value).to eq("MYR 500.00")
    expect(rows.fetch("Direct Bill Closed At").value).to eq("01 Jun 2026, 08:15 AM")
    expect(rows.fetch("Audit Flags").value).to eq("Imported: true")
  end

  it "uses due-on-receipt wording for zero-day terms" do
    invoice.update!(metadata: { payment_terms_days: 0 })

    expect(presenter.payment_terms_label).to eq("Due on receipt")
  end
end
