# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPayments::AutoAllocate do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, :superadmin) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel) }

  it "applies the payment to the oldest due invoice first, leaving newer invoices untouched" do
    older = create_invoice(amount: 200, due_on: 10.days.from_now)
    newer = create_invoice(amount: 200, due_on: 20.days.from_now)
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 150, currency: hotel.default_currency)

    result = described_class.call(payment: payment, user: user)

    expect(result).to be_success
    expect(older.reload).to have_attributes(paid_amount: 150.to_d, outstanding_amount: 50.to_d, status: "partially_paid")
    expect(newer.reload).to have_attributes(paid_amount: 0.to_d, outstanding_amount: 200.to_d, status: "open")
    expect(payment.reload.unallocated_amount).to eq(0.to_d)
  end

  it "spills over into the next oldest invoice once the first is fully paid" do
    older = create_invoice(amount: 100, due_on: 5.days.from_now)
    newer = create_invoice(amount: 200, due_on: 15.days.from_now)
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 180, currency: hotel.default_currency)

    result = described_class.call(payment: payment, user: user)

    expect(result).to be_success
    expect(older.reload).to have_attributes(outstanding_amount: 0.to_d, status: "paid")
    expect(newer.reload).to have_attributes(paid_amount: 80.to_d, outstanding_amount: 120.to_d, status: "partially_paid")
    expect(payment.reload.unallocated_amount).to eq(0.to_d)
  end

  it "leaves any excess amount unapplied as credit once all open invoices are settled" do
    invoice = create_invoice(amount: 100, due_on: 5.days.from_now)
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 150, currency: hotel.default_currency)

    result = described_class.call(payment: payment, user: user)

    expect(result).to be_success
    expect(invoice.reload).to have_attributes(outstanding_amount: 0.to_d, status: "paid")
    expect(payment.reload.unallocated_amount).to eq(50.to_d)
  end

  it "does nothing and reports success when there are no open invoices" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100, currency: hotel.default_currency)

    result = described_class.call(payment: payment, user: user)

    expect(result).to be_success
    expect(result.allocations).to eq([])
    expect(payment.reload.unallocated_amount).to eq(100.to_d)
  end

  it "only considers invoices for the payment's own corporate account and currency" do
    other_relationship = create(:hotel_corporate_account, hotel: hotel)
    create_invoice(amount: 100, due_on: 5.days.from_now, relationship: other_relationship)
    create_invoice(amount: 100, due_on: 5.days.from_now, currency: "USD")
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100, currency: hotel.default_currency)

    result = described_class.call(payment: payment, user: user)

    expect(result).to be_success
    expect(result.allocations).to eq([])
    expect(payment.reload.unallocated_amount).to eq(100.to_d)
  end

  def create_invoice(amount:, due_on:, relationship: self.relationship, currency: hotel.default_currency)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: currency, due_on: due_on)
  end
end
