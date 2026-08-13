# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::AccountsReceivable::ShowPresenter do
  subject(:presenter) { described_class.new(invoice: invoice) }

  let(:hotel) { create(:hotel, status: "live", default_currency: "MYR", time_zone: "Kuala Lumpur") }
  let(:account) { create(:account, :corporate, name: "Orion Capital") }
  let(:relationship) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      corporate_account: account,
      payment_terms_days: 30,
      credit_currency: "MYR"
    )
  end
  let(:booking) { create(:booking, hotel: hotel, confirmation_token: "BK-ORION") }
  let(:folio) { create(:booking_folio, :secondary, hotel: hotel, booking: booking, hotel_corporate_account: relationship, folio_number: 811) }
  let(:invoice) do
    create(
      :ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      invoice_number: 55,
      status: "partially_paid",
      amount: 600,
      paid_amount: 200,
      outstanding_amount: 400,
      currency: "MYR",
      issued_on: Date.new(2026, 6, 1),
      due_on: Date.new(2026, 7, 1),
      created_at: Time.utc(2026, 6, 1, 1, 0),
      metadata: {
        payment_terms_days: 14,
        direct_bill_closed_at: "2026-06-01T00:45:00Z"
      }
    )
  end

  describe "identity and amounts" do
    it "exposes invoice label, hotel name, and booking reference" do
      expect(presenter.invoice_label).to eq(invoice.formatted_invoice_number)
      expect(presenter.hotel_name).to eq(hotel.name)
      expect(presenter.booking_reference).to eq("BK-ORION")
    end

    it "formats amount labels in currency" do
      expect(presenter.original_amount_label).to eq("MYR 600.00")
      expect(presenter.paid_amount_label).to eq("MYR 200.00")
      expect(presenter.outstanding_amount_label).to eq("MYR 400.00")
    end

    it "reports has_outstanding_balance? correctly" do
      expect(presenter.has_outstanding_balance?).to be(true)
    end

    it "reports false for has_outstanding_balance? when invoice is fully paid" do
      invoice.update!(paid_amount: 600, outstanding_amount: 0, status: "paid")
      expect(described_class.new(invoice: invoice.reload).has_outstanding_balance?).to be(false)
    end
  end

  describe "status badge" do
    it "humanises the status label" do
      expect(presenter.status_label).to eq("Partially paid")
    end

    it "returns the correct colour class for each status" do
      {
        "open" => "bg-blue-50",
        "partially_paid" => "bg-amber-50",
        "paid" => "bg-emerald-50",
        "overdue" => "bg-red-50",
        "void" => "bg-slate-100"
      }.each do |status, expected|
        invoice.update_columns(status: status)
        expect(described_class.new(invoice: invoice.reload).status_class).to include(expected)
      end
    end
  end

  describe "detail fields" do
    it "reads payment terms from metadata first, then falls back to the relationship" do
      expect(presenter.payment_terms_label).to eq("Net 14 days")

      invoice.update!(metadata: {})
      expect(described_class.new(invoice: invoice.reload).payment_terms_label).to eq("Net 30 days")
    end

    it "uses 'Due on receipt' when payment_terms_days is 0" do
      invoice.update!(metadata: { payment_terms_days: 0 })
      expect(described_class.new(invoice: invoice.reload).payment_terms_label).to eq("Due on receipt")
    end

    it "returns — when payment terms is nil on both metadata and relationship" do
      invoice.update!(metadata: {})
      relationship.update!(payment_terms_days: nil)
      expect(described_class.new(invoice: invoice.reload).payment_terms_label).to eq("—")
    end

    it "formats issued_on and due_on dates" do
      expect(presenter.issued_on_label).to eq("01 Jun 2026")
      expect(presenter.due_on_label).to eq("01 Jul 2026")
    end

    it "labels direct_bill_source as 'Folio close' when metadata contains the timestamp" do
      expect(presenter.direct_bill_source_label).to eq("Folio close")
    end

    it "returns — for direct_bill_source when metadata has no timestamp" do
      invoice.update!(metadata: {})
      expect(described_class.new(invoice: invoice.reload).direct_bill_source_label).to eq("—")
    end

    it "formats created_at in the hotel time zone" do
      # Hotel is Kuala Lumpur (UTC+8), so UTC 01:00 → 09:00 local
      expect(presenter.created_at_label).to eq("01 Jun 2026, 09:00 AM")
    end
  end

  describe "allocation_rows" do
    it "returns active allocations sorted newest first" do
      older = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 50, currency: "MYR",
                     reference_number: "BANK-OLD", received_at: Date.new(2026, 6, 5), payment_method: "bank_transfer")
      newer = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 75, currency: "MYR",
                     reference_number: "CHQ-NEW", received_at: Date.new(2026, 6, 10), payment_method: "cheque")

      create(:ar_payment_allocation, ar_payment: older, ar_invoice: invoice, amount: 50)
      create(:ar_payment_allocation, ar_payment: newer, ar_invoice: invoice, amount: 75)

      rows = described_class.new(invoice: invoice.reload).allocation_rows

      expect(rows.map(&:reference)).to eq([ "CHQ-NEW", "BANK-OLD" ])
      expect(rows.first).to have_attributes(
        received_on: "10 Jun 2026",
        payment_method: "Cheque",
        allocated_amount: "MYR 75.00"
      )
    end

    it "excludes reversed allocations" do
      payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100, currency: "MYR",
                       reference_number: "REVERSED-REF", received_at: Date.current, payment_method: "cash")
      allocation = create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 100)
      create(:ar_payment_allocation_reversal, ar_payment_allocation: allocation, reason: "error")

      rows = described_class.new(invoice: invoice.reload).allocation_rows
      expect(rows.map(&:reference)).not_to include("REVERSED-REF")
    end

    it "returns an empty array when no allocations exist" do
      expect(presenter.allocation_rows).to be_empty
    end

    it "shows — for a blank reference number" do
      payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 30, currency: "MYR",
                       reference_number: "REF-X", received_at: Date.current, payment_method: "other")
      create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 30)

      row = described_class.new(invoice: invoice.reload).allocation_rows.first
      expect(row.reference).to eq("REF-X")
    end
  end
end
