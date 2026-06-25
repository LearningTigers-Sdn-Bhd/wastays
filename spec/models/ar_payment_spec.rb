# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPayment, type: :model do
  it "derives allocation status using active allocations only" do
    payment = create(:ar_payment, amount: 100)
    booking = create(:booking, hotel: payment.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: payment.hotel, hotel_corporate_account: payment.hotel_corporate_account)
    invoice = create(:ar_invoice, hotel: payment.hotel, booking_folio: folio, hotel_corporate_account: payment.hotel_corporate_account, amount: 100, outstanding_amount: 100)
    allocation = create(:ar_payment_allocation, ar_payment: payment, ar_invoice: invoice, amount: 40)

    expect(payment.reload).to have_attributes(allocated_amount: 40.to_d, unallocated_amount: 60.to_d)
    expect(payment.allocation_status).to eq("partially_allocated")

    create(:ar_payment_allocation_reversal, ar_payment_allocation: allocation)

    expect(payment.reload).to have_attributes(allocated_amount: 0.to_d, unallocated_amount: 100.to_d)
    expect(payment.allocation_status).to eq("unapplied")
  end

  it "is immutable" do
    payment = create(:ar_payment)

    expect(payment.update(reference_number: "CHANGED")).to eq(false)
    expect(payment.errors[:base]).to include("AR payments are immutable.")
  end
end
