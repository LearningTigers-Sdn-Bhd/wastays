# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::ArPayments::IndexPresenter do
  let(:hotel) { create(:hotel) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel) }

  it "reports active allocations and unapplied balances while excluding reversals" do
    payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 500, currency: hotel.default_currency, received_at: hotel.current_business_date)
    create(:ar_payment_allocation, ar_payment: payment, ar_invoice: create_invoice(amount: 100), amount: 100)
    reversed = create(:ar_payment_allocation, ar_payment: payment, ar_invoice: create_invoice(amount: 50), amount: 50)
    create(:ar_payment_allocation_reversal, ar_payment_allocation: reversed)

    presenter = described_class.new(hotel: hotel, params: {})
    metrics = presenter.summary_metrics.index_by(&:label)
    row = presenter.paginated_rows.first

    expect(metrics.fetch("Allocated This Month").amounts).to eq([ "#{hotel.default_currency} 100.00" ])
    expect(metrics.fetch("Total Unapplied").amounts).to eq([ "#{hotel.default_currency} 400.00" ])
    expect(metrics.fetch("Needs Allocation").amounts).to eq([ "1" ])
    expect(row).to have_attributes(
      allocated_label: "#{hotel.default_currency} 100.00",
      unapplied_label: "#{hotel.default_currency} 400.00",
      status: "partially_allocated"
    )
  end

  it "filters by derived allocation status" do
    create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100)
    fully_allocated = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100)
    create(:ar_payment_allocation, ar_payment: fully_allocated, ar_invoice: create_invoice(amount: 100), amount: 100)

    presenter = described_class.new(hotel: hotel, params: { status: "fully_allocated" })

    expect(presenter.paginated_rows.map(&:payment)).to contain_exactly(fully_allocated)
  end

  def create_invoice(amount:)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, paid_amount: 0, outstanding_amount: amount, currency: hotel.default_currency)
  end
end
