# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPayments::RecordPayment do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel) }

  it "records one payment against one invoice" do
    invoice = create_invoice(amount: 100)

    expect {
      @result = call_service(amount: 100, allocations: { invoice.id => "100.00" })
    }.to change(ArPayment, :count).by(1)
      .and change(ArPaymentAllocation, :count).by(1)
      .and change(FinancialAuditEvent.where(event_type: "ar_payment_recorded"), :count).by(1)

    expect(@result).to be_success
    expect(invoice.reload).to have_attributes(paid_amount: 100.to_d, outstanding_amount: 0.to_d, status: "paid")
    expect(@result.ar_payment.reference_number).to eq("BANK-1")
  end

  it "records one payment against multiple invoices" do
    invoice_one = create_invoice(amount: 100)
    invoice_two = create_invoice(amount: 200)

    result = call_service(amount: 250, allocations: { invoice_one.id => "100.00", invoice_two.id => "150.00" })

    expect(result).to be_success
    expect(result.ar_payment.ar_payment_allocations.count).to eq(2)
    expect(invoice_one.reload).to be_paid
    expect(invoice_two.reload).to have_attributes(paid_amount: 150.to_d, outstanding_amount: 50.to_d, status: "partially_paid")
  end

  it "supports partial payment" do
    invoice = create_invoice(amount: 100)

    result = call_service(amount: 40, allocations: { invoice.id => "40.00" })

    expect(result).to be_success
    expect(invoice.reload).to have_attributes(paid_amount: 40.to_d, outstanding_amount: 60.to_d, status: "partially_paid")
  end

  it "records a fully unapplied payment" do
    result = call_service(amount: 100, allocations: {})

    expect(result).to be_success
    expect(result.ar_payment).to have_attributes(allocated_amount: 0.to_d, unallocated_amount: 100.to_d)
    expect(result.ar_payment.allocation_status).to eq("unapplied")
  end

  it "keeps AR payments separate from guest folio payments" do
    invoice = create_invoice(amount: 100)

    expect {
      call_service(amount: 100, allocations: { invoice.id => "100.00" })
    }.not_to change(FolioTransaction, :count)
  end

  it "prevents allocation beyond payment amount" do
    invoice = create_invoice(amount: 100)

    result = call_service(amount: 50, allocations: { invoice.id => "80.00" })

    expect(result).not_to be_success
    expect(result.error).to eq("Allocation total cannot exceed payment amount.")
    expect(invoice.reload).to have_attributes(paid_amount: 0.to_d, outstanding_amount: 100.to_d, status: "open")
  end

  it "prevents allocation beyond invoice outstanding amount" do
    invoice = create_invoice(amount: 100)

    result = call_service(amount: 120, allocations: { invoice.id => "120.00" })

    expect(result).not_to be_success
    expect(result.error).to eq("Allocation for AR-#{invoice.invoice_number} exceeds outstanding amount.")
  end

  def call_service(amount:, allocations:)
    described_class.call(
      hotel: hotel,
      hotel_corporate_account: relationship,
      user: user,
      amount: amount,
      currency: hotel.default_currency,
      reference_number: "BANK-1",
      received_at: Date.current,
      payment_method: "bank_transfer",
      allocations: allocations
    )
  end

  def create_invoice(amount:)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: hotel.default_currency)
  end
end
