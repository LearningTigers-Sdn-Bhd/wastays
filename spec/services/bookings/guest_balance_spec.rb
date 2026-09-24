require "rails_helper"

RSpec.describe Bookings::GuestBalance do
  let(:booking) { build_stubbed(:booking, total_amount: 500, payment_status: "pending") }

  def folio(charges:, payments:, forecasts: [])
    instance_double(BookingFolio,
      total_charges: charges.to_d,
      total_payments: payments.to_d,
      projected_forecasts: forecasts.map { |amount| instance_double(FolioForecastedCharge, amount: amount.to_d) })
  end

  def balance_with(*folios)
    allow(booking).to receive(:booking_folios).and_return(folios)
    described_class.new(booking:).call
  end

  it "totals posted and forecast charges and takes the folio payments" do
    result = balance_with(folio(charges: 300, payments: 250, forecasts: [ 100 ]))

    expect(result).to have_attributes(total: 400, paid: 250, due: 150)
  end

  it "falls back to the booked total before any charge is posted" do
    result = balance_with

    expect(result).to have_attributes(total: 500, paid: 0, due: 500)
  end

  it "counts a payment captured online as paid, without counting it twice" do
    booking.payment_status = "captured"

    expect(balance_with).to have_attributes(paid: 500, due: 0)
    expect(balance_with(folio(charges: 500, payments: 500))).to have_attributes(paid: 500, due: 0)
  end
end
