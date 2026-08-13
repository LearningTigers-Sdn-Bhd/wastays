# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::AccountsReceivable::IndexPresenter do
  subject(:presenter) { described_class.new(account: account, params: params) }

  let(:account) { create(:account, :corporate) }
  let(:hotel) { create(:hotel, status: "live", default_currency: "MYR") }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, corporate_account: account, credit_currency: "MYR") }
  let(:params) { {} }

  describe "data scoping" do
    it "only surfaces invoices belonging to the account" do
      visible = create_invoice(relationship: relationship, confirmation_token: "BK-MINE", folio_number: 101, amount: 200)
      other_relationship = create(:hotel_corporate_account)
      _hidden = create_invoice(relationship: other_relationship, confirmation_token: "BK-OTHER", folio_number: 999, amount: 500)

      expect(presenter.paginated_rows.map(&:invoice_label)).to eq([ visible.formatted_invoice_number ])
    end
  end

  describe "filtering" do
    let(:second_hotel) { create(:hotel, status: "live", default_currency: "MYR", name: "Seaside Resort") }
    let(:second_relationship) { create(:hotel_corporate_account, hotel: second_hotel, corporate_account: account, credit_currency: "MYR") }

    before do
      create_invoice(relationship: relationship, confirmation_token: "BK-FIRST", folio_number: 201, invoice_number: 500_201, status: "open", due_on: Date.new(2026, 7, 10), amount: 100)
      create_invoice(relationship: second_relationship, confirmation_token: "BK-SECOND", folio_number: 202, invoice_number: 700_202, status: "paid", due_on: Date.new(2026, 8, 1), amount: 50, paid_amount: 50, outstanding_amount: 0)
    end

    it "searches by invoice number, booking reference, and hotel name" do
      first_invoice = relationship.ar_invoices.first

      expect(presenter_for(query: first_invoice.invoice_number.to_s).paginated_rows.map(&:booking_reference)).to eq([ "BK-FIRST" ])
      expect(presenter_for(query: "BK-FIRST").paginated_rows.map(&:booking_reference)).to eq([ "BK-FIRST" ])
      expect(presenter_for(query: "BK-SECOND").paginated_rows.map(&:booking_reference)).to eq([ "BK-SECOND" ])
      expect(presenter_for(query: "Seaside").paginated_rows.map(&:booking_reference)).to eq([ "BK-SECOND" ])
    end

    it "filters by status" do
      expect(presenter_for(status: "open").paginated_rows.map(&:booking_reference)).to eq([ "BK-FIRST" ])
      expect(presenter_for(status: "paid").paginated_rows.map(&:booking_reference)).to eq([ "BK-SECOND" ])
    end

    it "filters by hotel" do
      expect(presenter_for(hotel_id: hotel.id).paginated_rows.map(&:booking_reference)).to eq([ "BK-FIRST" ])
      expect(presenter_for(hotel_id: second_hotel.id).paginated_rows.map(&:booking_reference)).to eq([ "BK-SECOND" ])
    end

    it "filters by exact due date" do
      result = presenter_for(due_on: "2026-07-10")
      expect(result.paginated_rows.map(&:booking_reference)).to eq([ "BK-FIRST" ])
    end

    it "filters to invoices with outstanding balance" do
      result = presenter_for(balance: "outstanding")
      expect(result.paginated_rows.map(&:booking_reference)).to eq([ "BK-FIRST" ])
      expect(result.selected_balance).to eq("outstanding")
      expect(result.filters_active?).to be(true)
    end

    it "ignores invalid status, hotel, date, and balance params without leaking other accounts' data" do
      result = presenter_for(status: "not-a-status", hotel_id: "9999999", due_on: "not-a-date", balance: "infinite")
      expect(result.paginated_rows.map(&:booking_reference)).to contain_exactly("BK-FIRST", "BK-SECOND")
      expect(result.filters_active?).to be(false)
    end

    it "carries active filter params into pagination_params" do
      result = presenter_for(status: "open", hotel_id: hotel.id)
      expect(result.pagination_params).to include(status: "open", hotel_id: hotel.id.to_s)
    end
  end

  describe "hotel_options" do
    it "lists only active hotel relationships sorted by hotel name" do
      hotel_a = create(:hotel, status: "live", name: "Zenith Hotel")
      hotel_b = create(:hotel, status: "live", name: "Apex Suites")
      rel_a = create(:hotel_corporate_account, hotel: hotel_a, corporate_account: account, credit_currency: "MYR")
      rel_b = create(:hotel_corporate_account, hotel: hotel_b, corporate_account: account, credit_currency: "MYR")
      suspended = create(:hotel_corporate_account, hotel: create(:hotel, status: "live"), corporate_account: account, credit_currency: "MYR", status: "suspended")

      option_ids = presenter.hotel_options.map(&:id)
      expect(option_ids).to include(hotel_a.id, hotel_b.id)
      expect(option_ids).not_to include(suspended.hotel_id)
      expect(presenter.hotel_options.map(&:name)).to eq(presenter.hotel_options.map(&:name).sort)
    end
  end

  describe "summary metrics" do
    it "computes Open AR, Overdue, Due Soon, and Received This Month across all linked hotels" do
      today = Date.current

      create_invoice(relationship: relationship, amount: 120, due_on: today - 5.days, status: "overdue")
      create_invoice(relationship: relationship, amount: 80, due_on: today + 3.days)
      create_invoice(relationship: relationship, amount: 60, due_on: today + 30.days)

      second_relationship = create(:hotel_corporate_account, hotel: create(:hotel, status: "live"), corporate_account: account, credit_currency: "MYR")
      create_invoice(relationship: second_relationship, amount: 50, currency: "USD", due_on: today + 2.days)

      create(:ar_payment, hotel: relationship.hotel, hotel_corporate_account: relationship, amount: 100, currency: "MYR", received_at: today)
      create(:ar_payment, hotel: relationship.hotel, hotel_corporate_account: relationship, amount: 999, currency: "MYR", received_at: today - 2.months)

      metrics = presenter.summary_metrics.index_by(&:label)

      # Open AR: 120 (overdue) + 80 (due soon) + 60 (future) = 260 MYR + 50 USD
      expect(metrics.fetch("Open AR").amounts).to contain_exactly("MYR 260.00", "USD 50.00")
      expect(metrics.fetch("Overdue").amounts).to eq([ "MYR 120.00" ])
      expect(metrics.fetch("Due Soon").amounts).to contain_exactly("MYR 80.00", "USD 50.00")
      expect(metrics.fetch("Received This Month").amounts).to eq([ "MYR 100.00" ])
    end

    it "returns a zero amount when no records exist" do
      result = presenter.summary_metrics
      expect(result).to all(satisfy { |metric| metric.amounts.first.end_with?("0.00") })
    end
  end

  describe "pagination" do
    it "paginates at 25 rows" do
      26.times { |i| create_invoice(relationship: relationship, confirmation_token: "BK-P-#{i}", folio_number: 3_000 + i) }

      expect(presenter.paginated_rows.size).to eq(25)
      expect(presenter.pagination.total_pages).to eq(2)
    end
  end

  describe "Row" do
    it "formats all labels and applies correct status styling" do
      invoice = create_invoice(
        relationship: relationship,
        confirmation_token: "BK-ROW",
        folio_number: 500,
        amount: 300,
        paid_amount: 150,
        outstanding_amount: 150,
        status: "partially_paid",
        issued_on: Date.new(2026, 6, 1),
        due_on: Date.new(2026, 6, 30)
      )

      row = described_class::Row.new(invoice)

      expect(row.invoice_label).to eq(invoice.formatted_invoice_number)
      expect(row.hotel_name).to eq(hotel.name)
      expect(row.booking_reference).to eq("BK-ROW")
      expect(row.folio_reference).to include("500")
      expect(row.issued_on_label).to eq("01 Jun 2026")
      expect(row.due_on_label).to eq("30 Jun 2026")
      expect(row.outstanding_amount_label).to eq("MYR 150.00")
      expect(row.status_label).to eq("Partially paid")
      expect(row.status_class).to include("bg-amber-50")
    end

    it "maps all statuses to distinct colour classes" do
      statuses = {
        "open" => "bg-blue-50",
        "paid" => "bg-emerald-50",
        "overdue" => "bg-red-50",
        "void" => "bg-slate-100"
      }

      statuses.each do |status, expected_class|
        invoice = create_invoice(relationship: relationship, confirmation_token: "BK-#{status}", folio_number: rand(10_000..99_999), status: status)
        expect(described_class::Row.new(invoice).status_class).to include(expected_class), "expected #{status} → #{expected_class}"
      end
    end
  end

  # ---------------------------------------------------------------------------

  def presenter_for(overrides)
    described_class.new(account: account, params: overrides)
  end

  def create_invoice(
    relationship:,
    confirmation_token: "BK-#{SecureRandom.hex(4)}",
    folio_number: nil,
    invoice_number: nil,
    amount: 100,
    paid_amount: 0,
    outstanding_amount: nil,
    currency: "MYR",
    status: "open",
    issued_on: Date.current,
    due_on: Date.current + 30.days
  )
    outstanding_amount ||= amount - paid_amount
    booking = create(:booking, hotel: relationship.hotel, confirmation_token: confirmation_token, currency: currency)
    folio_number ||= BookingFolio.maximum(:folio_number).to_i + 1
    invoice_number ||= ArInvoice.maximum(:invoice_number).to_i + 1
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, folio_number: folio_number, hotel_corporate_account: relationship, currency: currency)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship,
           invoice_number: invoice_number, amount: amount, paid_amount: paid_amount, outstanding_amount: outstanding_amount,
           currency: currency, status: status, issued_on: issued_on, due_on: due_on)
  end
end
