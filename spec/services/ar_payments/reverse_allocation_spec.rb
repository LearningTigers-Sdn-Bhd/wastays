# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPayments::ReverseAllocation do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel) }
  let(:invoice) do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: 500, paid_amount: 400, outstanding_amount: 100, status: "partially_paid", currency: hotel.default_currency)
  end
  let(:payment) { create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 400, currency: hotel.default_currency) }
  let(:allocation) { create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 400) }

  it "reverses the full allocation and restores invoice and payment balances" do
    expect {
      @result = described_class.call(allocation: allocation, user: user, reason: "Applied to the wrong invoice")
    }.to change(ArPaymentAllocationReversal, :count).by(1)
      .and change(FinancialAuditEvent.where(event_type: "ar_payment_allocation_reversed"), :count).by(1)

    expect(@result).to be_success
    expect(payment.reload).to have_attributes(allocated_amount: 0.to_d, unallocated_amount: 400.to_d)
    expect(invoice.reload).to have_attributes(paid_amount: 0.to_d, outstanding_amount: 500.to_d, status: "open")
    expect(allocation.reload.reversal).to have_attributes(reason: "Applied to the wrong invoice", reversed_by: user)
  end

  it "requires a reason" do
    result = described_class.call(allocation: allocation, user: user, reason: "")

    expect(result).not_to be_success
    expect(result.error).to eq("Reversal reason is required.")
  end

  it "does not reverse the same allocation twice" do
    create(:ar_payment_allocation_reversal, ar_payment_allocation: allocation, reversed_by: user)

    result = described_class.call(allocation: allocation, user: user, reason: "Again")

    expect(result).not_to be_success
    expect(result.error).to eq("This allocation has already been reversed.")
  end
end
