# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPayments::AllocatePayment do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel) }
  let(:payment) { create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 400, currency: hotel.default_currency) }

  it "allocates an unapplied balance and leaves the remaining invoice amount outstanding" do
    invoice = create_invoice(amount: 500)

    expect {
      @result = described_class.call(payment: payment, user: user, allocations: { invoice.id => "400.00" })
    }.to change(ArPaymentAllocation, :count).by(1)
      .and change(FinancialAuditEvent.where(event_type: "ar_payment_allocated"), :count).by(1)

    expect(@result).to be_success
    expect(payment.reload.unallocated_amount).to eq(0.to_d)
    expect(invoice.reload).to have_attributes(paid_amount: 400.to_d, outstanding_amount: 100.to_d, status: "partially_paid")
  end

  it "supports allocating the same payment to the same invoice more than once" do
    invoice = create_invoice(amount: 500)

    first = described_class.call(payment: payment, user: user, allocations: { invoice.id => "250.00" })
    second = described_class.call(payment: payment.reload, user: user, allocations: { invoice.id => "150.00" })

    expect(first).to be_success
    expect(second).to be_success
    expect(payment.ar_payment_allocations.where(ar_invoice: invoice).count).to eq(2)
  end

  it "rejects allocation beyond the unapplied balance" do
    invoice = create_invoice(amount: 500)

    result = described_class.call(payment: payment, user: user, allocations: { invoice.id => "401.00" })

    expect(result).not_to be_success
    expect(result.error).to eq("Allocation total cannot exceed the payment's unapplied balance.")
    expect(invoice.reload.outstanding_amount).to eq(500.to_d)
  end

  it "rejects invoices from another corporate account" do
    other_relationship = create(:hotel_corporate_account, hotel: hotel)
    invoice = create_invoice(amount: 100, relationship: other_relationship)

    result = described_class.call(payment: payment, user: user, allocations: { invoice.id => "100.00" })

    expect(result).not_to be_success
    expect(result.error).to eq("Invoice #{invoice.id} is not available for this payment.")
  end

  it "rejects invoices from another hotel or currency" do
    other_hotel = create(:hotel)
    other_relationship = create(:hotel_corporate_account, hotel: other_hotel)
    other_booking = create(:booking, hotel: other_hotel)
    other_folio = create(:booking_folio, :secondary, booking: other_booking, hotel: other_hotel, hotel_corporate_account: other_relationship)
    other_invoice = create(:ar_invoice, hotel: other_hotel, booking_folio: other_folio, hotel_corporate_account: other_relationship, amount: 100, outstanding_amount: 100, currency: other_hotel.default_currency)
    currency_invoice = create_invoice(amount: 100, currency: "USD")

    other_hotel_result = described_class.call(payment: payment, user: user, allocations: { other_invoice.id => "50.00" })
    currency_result = described_class.call(payment: payment, user: user, allocations: { currency_invoice.id => "50.00" })

    expect(other_hotel_result.error).to eq("Invoice #{other_invoice.id} is not available for this payment.")
    expect(currency_result.error).to eq("Invoice #{currency_invoice.id} is not available for this payment.")
  end

  it "rejects paid and void invoices" do
    paid_invoice = create_invoice(amount: 100)
    paid_invoice.update!(paid_amount: 100, outstanding_amount: 0, status: "paid")
    void_invoice = create_invoice(amount: 100)
    void_invoice.update!(status: "void")

    paid_result = described_class.call(payment: payment, user: user, allocations: { paid_invoice.id => "50.00" })
    void_result = described_class.call(payment: payment, user: user, allocations: { void_invoice.id => "50.00" })

    expect(paid_result.error).to eq("Invoice #{paid_invoice.id} is not available for this payment.")
    expect(void_result.error).to eq("Invoice #{void_invoice.id} is not available for this payment.")
  end

  def create_invoice(amount:, relationship: self.relationship, currency: hotel.default_currency)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: currency)
  end
end
