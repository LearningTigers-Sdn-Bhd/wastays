# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reports::AccountsReceivable::GenerateStatementRecords do
  let(:hotel) { create(:hotel, default_currency: "MYR", time_zone: "Asia/Kuala_Lumpur") }
  let(:corporate_account) { create(:account, :corporate, name: "Atlas Travel") }
  let(:relationship) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      corporate_account: corporate_account,
      credit_currency: "MYR",
      payment_terms_days: 30
    )
  end
  let!(:contact) { create(:user, :corporate, account: corporate_account, email: "billing@atlas.test") }
  let(:start_date) { Date.new(2026, 6, 1) }
  let(:end_date) { Date.new(2026, 6, 30) }

  before do
    allow(hotel).to receive(:current_business_date).and_return(Date.new(2026, 6, 30))
  end

  it "builds opening, period, closing, and running balances from invoices and received payments" do
    create_invoice(amount: 100, issued_on: Date.new(2026, 5, 1), due_on: Date.new(2026, 5, 31), token: "OPENING")
    create_payment(amount: 20, received_at: Date.new(2026, 5, 20), reference: "PAY-OPEN")
    period_invoice = create_invoice(amount: 200, issued_on: Date.new(2026, 6, 10), due_on: Date.new(2026, 7, 10), token: "PERIOD")
    create_payment(amount: 50, received_at: Date.new(2026, 6, 20), reference: "PAY-PERIOD")
    create_invoice(amount: 999, issued_on: Date.new(2026, 7, 1), due_on: Date.new(2026, 7, 31), token: "FUTURE")

    report = generate

    expect(report).to have_attributes(
      opening_balance: 80.to_d,
      period_invoices: 200.to_d,
      period_payments: 50.to_d,
      closing_balance: 230.to_d
    )
    expect(report.ledger_rows.map(&:reference)).to eq([ "AR-#{period_invoice.invoice_number}", "PAY-PERIOD" ])
    expect(report.ledger_rows.map(&:balance)).to eq([ 280.to_d, 230.to_d ])
    expect(report.contact_email).to eq("billing@atlas.test")
  end

  it "uses inclusive boundaries and deterministic invoice-before-payment ordering" do
    travel_to Time.zone.local(2026, 6, 1, 10, 0, 0) do
      create_invoice(amount: 75, issued_on: start_date, due_on: end_date, token: "BOUNDARY")
      create_payment(amount: 25, received_at: start_date, reference: "PAY-BOUNDARY")
    end

    report = generate

    expect(report.ledger_rows.map(&:record_type)).to eq([ "Invoice", "Payment" ])
    expect(report.ledger_rows.map(&:balance)).to eq([ 75.to_d, 50.to_d ])
  end

  it "reconstructs allocations and reversals as of the statement end date" do
    invoice = create_invoice(amount: 100, issued_on: Date.new(2026, 6, 1), due_on: Date.new(2026, 6, 15), token: "ALLOC")
    payment = create_payment(amount: 100, received_at: Date.new(2026, 6, 10), reference: "PAY-ALLOC")
    allocation = travel_to(Time.zone.local(2026, 6, 10, 12, 0, 0)) do
      create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 60)
    end
    travel_to Time.zone.local(2026, 7, 1, 9, 0, 0) do
      create(:ar_payment_allocation_reversal, ar_payment_allocation: allocation, reversed_by: create(:user), reversed_at: Time.current)
    end

    june_report = generate
    allow(hotel).to receive(:current_business_date).and_return(Date.new(2026, 7, 2))
    july_report = generate(end_date: Date.new(2026, 7, 2))

    expect(june_report.unapplied_credit).to eq(40.to_d)
    expect(june_report.aging.days_1_30).to eq(40.to_d)
    expect(june_report.ledger_rows.last.description).to include("Applied: AR-#{invoice.invoice_number} 60.00", "Unapplied: MYR 40.00")

    expect(july_report.unapplied_credit).to eq(100.to_d)
    expect(july_report.aging.days_1_30).to eq(100.to_d)
    expect(july_report.ledger_rows.last.description).to include("Unapplied: MYR 100.00")
    expect(july_report.ledger_rows.last.description).not_to include("Applied:")
  end

  it "ages reconstructed invoice balances and keeps unapplied credit separate" do
    create_invoice(amount: 10, issued_on: Date.new(2026, 6, 1), due_on: Date.new(2026, 7, 1), token: "CURRENT")
    create_invoice(amount: 20, issued_on: Date.new(2026, 5, 1), due_on: Date.new(2026, 6, 15), token: "30")
    create_invoice(amount: 30, issued_on: Date.new(2026, 4, 1), due_on: Date.new(2026, 5, 15), token: "60")
    create_invoice(amount: 40, issued_on: Date.new(2026, 3, 1), due_on: Date.new(2026, 4, 15), token: "90")
    create_invoice(amount: 50, issued_on: Date.new(2026, 1, 1), due_on: Date.new(2026, 3, 1), token: "OVER")
    create_payment(amount: 25, received_at: Date.new(2026, 6, 20), reference: "UNAPPLIED")

    report = generate

    expect(report.aging).to have_attributes(
      current: 10.to_d,
      days_1_30: 20.to_d,
      days_31_60: 30.to_d,
      days_61_90: 40.to_d,
      days_over_90: 50.to_d
    )
    expect(report.aging.total).to eq(150.to_d)
    expect(report.unapplied_credit).to eq(25.to_d)
  end

  it "excludes currently void invoices and discloses the historical restatement policy" do
    create_invoice(amount: 100, issued_on: start_date, due_on: end_date, token: "VOID", status: "void")

    report = generate

    expect(report.period_invoices).to eq(0.to_d)
    expect(report.ledger_rows).to be_empty
    expect(report.notes.join(" ")).to include("current void status")
  end

  it "keeps currencies separate and chooses the relationship currency when it has activity" do
    create_invoice(amount: 100, issued_on: start_date, due_on: end_date, token: "MYR", currency: "MYR")
    create_invoice(amount: 50, issued_on: start_date, due_on: end_date, token: "USD", currency: "USD")

    default_report = generate(currency: nil)
    usd_report = generate(currency: "USD")

    expect(default_report.currency).to eq("MYR")
    expect(default_report.available_currencies).to eq(%w[MYR USD])
    expect(default_report.period_invoices).to eq(100.to_d)
    expect(usd_report.period_invoices).to eq(50.to_d)
  end

  it "uses the credit currency for a zero-activity account" do
    report = generate

    expect(report.currency).to eq("MYR")
    expect(report.available_currencies).to eq([ "MYR" ])
    expect(report.closing_balance).to eq(0.to_d)
  end

  it "allows a negative closing balance when payments exceed invoices" do
    create_invoice(amount: 50, issued_on: start_date, due_on: end_date, token: "CREDIT")
    create_payment(amount: 125, received_at: end_date, reference: "OVERPAYMENT")

    report = generate

    expect(report.closing_balance).to eq(-75.to_d)
    expect(report.ledger_rows.last.balance).to eq(-75.to_d)
    expect(report.unapplied_credit).to eq(125.to_d)
  end

  it "rejects invalid periods, future end dates, unavailable currencies, and cross-hotel relationships" do
    expect { generate(start_date: end_date, end_date: start_date) }
      .to raise_error(described_class::InvalidStatementError, "Start date must be on or before end date.")
    expect { generate(end_date: Date.new(2026, 7, 1)) }
      .to raise_error(described_class::InvalidStatementError, "End date cannot be after the current business date.")
    expect { generate(currency: "USD") }
      .to raise_error(described_class::InvalidStatementError, "Currency is not available for this corporate account.")

    other_relationship = create(:hotel_corporate_account)
    expect {
      described_class.call(
        hotel: hotel,
        hotel_corporate_account: other_relationship,
        start_date: start_date,
        end_date: end_date
      )
    }.to raise_error(ActiveRecord::RecordNotFound)
  end

  def generate(start_date: self.start_date, end_date: self.end_date, currency: "MYR")
    described_class.call(
      hotel: hotel,
      hotel_corporate_account: relationship,
      start_date: start_date,
      end_date: end_date,
      currency: currency
    )
  end

  def create_invoice(amount:, issued_on:, due_on:, token:, currency: "MYR", status: "open")
    booking = create(:booking, hotel: hotel, confirmation_token: token, currency: currency)
    folio = create(
      :booking_folio,
      :secondary,
      booking: booking,
      hotel: hotel,
      hotel_corporate_account: relationship,
      currency: currency
    )
    create(
      :ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      amount: amount,
      outstanding_amount: amount,
      status: status,
      currency: currency,
      issued_on: issued_on,
      due_on: due_on
    )
  end

  def create_payment(amount:, received_at:, reference:, currency: "MYR")
    create(
      :ar_payment,
      hotel: hotel,
      hotel_corporate_account: relationship,
      amount: amount,
      currency: currency,
      reference_number: reference,
      received_at: received_at
    )
  end
end
