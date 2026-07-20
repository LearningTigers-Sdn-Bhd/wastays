# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueAccounting do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }
  let(:folio) { create(:booking_folio, booking: booking, hotel: hotel) }

  def tx(**attrs)
    create(:folio_transaction, booking_folio: folio, **attrs)
  end

  it "classifies signed buckets and derives totals" do
    accommodation = tx(category: "accommodation", amount: 100)
    service = tx(category: "fb", amount: 25)
    tax = tx(category: "tax", amount: 8)
    payment = tx(transaction_type: "payment", category: "cash", amount: 133)
    refund = tx(transaction_type: "payment", category: "refund", amount: -20)
    discount = tx(transaction_type: "adjustment", category: "discount", amount: -10)
    write_off = tx(transaction_type: "adjustment", category: "write_off", amount: -5)
    reversal = tx(transaction_type: "adjustment", category: "correction", amount: -100, reversal_of_transaction: accommodation)

    accounting = described_class.new([ accommodation, service, tax, payment, refund, discount, write_off, reversal ])

    expect(accounting.totals).to include(
      accommodation: 100.to_d,
      other_charges: 25.to_d,
      tax: 8.to_d,
      total_charges: 133.to_d,
      adjustments: -115.to_d,
      net_revenue: 18.to_d,
      total_payments: 133.to_d,
      refund: -20.to_d,
      net_payments: 113.to_d
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

  it "buckets a single transaction without abs" do
    accounting = described_class.new([])
    charge = tx(category: "accommodation", amount: 100)

    expect(accounting.bucket_for(charge)).to eq(accommodation: 100.to_d)

    refund = tx(transaction_type: "payment", category: "refund", amount: -20)
    expect(accounting.bucket_for(refund)).to eq(refund: -20.to_d)
  end
end
