# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueAccounting do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }

  def tx(**attrs)
    create(:folio_transaction, booking_folio: folio, **attrs)
  end

  it "classifies charge/adjustment buckets and derives totals, ignoring payments" do
    accommodation = tx(category: "accommodation", amount: 100)
    service = tx(category: "fb", amount: 25)
    tax = tx(category: "tax", amount: 8)
    payment = tx(transaction_type: "payment", category: "cash", amount: 133)
    discount = tx(transaction_type: "adjustment", category: "discount", amount: -10)
    write_off = tx(transaction_type: "adjustment", category: "write_off", amount: -5)

    accounting = described_class.new([ accommodation, service, tax, payment, discount, write_off ])

    expect(accounting.totals).to eq(
      accommodation: 100.to_d,
      day_use: 0.to_d,
      room_fees: 0.to_d,
      other_charges: 25.to_d,
      tax: 8.to_d,
      adjustments: -15.to_d,
      total_charges: 133.to_d,
      net_revenue: 118.to_d
    )
  end

  it "keeps original and reversing transactions as separate signed inputs" do
    original = tx(category: "accommodation", amount: 100)
    reversal = tx(transaction_type: "adjustment", category: "correction", amount: -100, reversal_of_transaction: original)

    accounting = described_class.new([ original, reversal ])

    expect(accounting.totals[:accommodation]).to eq(100.to_d)
    expect(accounting.totals[:adjustments]).to eq(-100.to_d)
    expect(accounting.totals[:net_revenue]).to eq(0.to_d)
  end

  it "buckets a single charge transaction without abs" do
    accounting = described_class.new([])
    charge = tx(category: "accommodation", amount: 100)

    expect(accounting.bucket_for(charge)).to eq(accommodation: 100.to_d)
  end

  it "ignores payment transactions entirely (they belong to Cashier Sales)" do
    accounting = described_class.new([])
    payment = tx(transaction_type: "payment", category: "refund", amount: -20)

    expect(accounting.bucket_for(payment)).to eq({})
  end

  it "puts no-show, early departure, late checkout and cancellation fees in room fees" do
    fees = %w[no_show_charge early_departure_charge late_checkout_charge cancellation_charge].map { |category| tx(category: category, amount: 10) }
    extra = tx(category: "other", amount: 5)

    accounting = described_class.new(fees + [ extra ])

    expect(accounting.totals).to include(room_fees: 40.to_d, other_charges: 5.to_d, accommodation: 0.to_d, total_charges: 45.to_d)
    expect(fees.map { |fee| accounting.extra_charge?(fee) }).to all(be(false))
    expect(accounting.extra_charge?(extra)).to be(true)
  end
end
