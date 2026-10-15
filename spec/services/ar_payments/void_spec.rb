# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPayments::Void do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel) }
  let(:payment) { create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 400, currency: hotel.default_currency) }

  def call(reason: "Recorded in error")
    described_class.call(payment: payment, user: user, reason: reason)
  end

  it "voids the payment, voids the receipt and records an audit event" do
    expect { @result = call }
      .to change(ArPaymentVoid, :count).by(1)
      .and change(FinancialAuditEvent.where(event_type: "ar_payment_voided"), :count).by(1)

    expect(@result).to be_success
    expect(payment.reload).to be_voided
    expect(payment.unallocated_amount).to eq(0.to_d)
    expect(payment.allocation_status).to eq("voided")
    expect(payment.receipt.status).to eq("voided")
    expect(payment.void).to have_attributes(reason: "Recorded in error", voided_by: user)
  end

  it "requires a reason" do
    result = call(reason: " ")

    expect(result).not_to be_success
    expect(result.error).to eq("Void reason is required.")
  end

  it "does not void twice" do
    call
    result = call

    expect(result).not_to be_success
    expect(result.error).to eq("This payment is already voided.")
  end

  it "blocks a payment with an active allocation" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    invoice = create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: 400, currency: hotel.default_currency)
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 400)

    result = call

    expect(result).not_to be_success
    expect(result.error).to eq("Reverse the active allocations before voiding this payment.")
    expect(payment.reload).not_to be_voided
  end

  it "voids a payment whose allocations were all reversed" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    invoice = create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: 400, currency: hotel.default_currency)
    allocation = create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 400)
    create(:ar_payment_allocation_reversal, ar_payment_allocation: allocation, reversed_by: user)

    expect(call).to be_success
  end

  it "blocks a gateway payment" do
    gateway_payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, metadata: { "source" => "corporate_portal_gateway" })

    result = described_class.call(payment: gateway_payment, user: user, reason: "Mistake")

    expect(result).not_to be_success
    expect(result.error).to match(/gateway/)
  end

  it "blocks allocating a voided payment" do
    call
    result = ArPayments::AllocatePayment.call(payment: payment.reload, user: user, allocations: { 1 => "10" })

    expect(result).not_to be_success
  end

  it "stays out of the not_voided scope" do
    call

    expect(ArPayment.not_voided).not_to include(payment)
  end
end
