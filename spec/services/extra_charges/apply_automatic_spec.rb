require "rails_helper"

RSpec.describe ExtraCharges::ApplyAutomatic do
  let(:business_date) { Date.new(2026, 8, 3) }
  let(:hotel) { create(:hotel, accounting_business_date: business_date) }
  let(:booking) do
    create(:booking, hotel: hotel, status: "confirmed", adults: 2, children: 0,
      check_in: business_date + 1.day, check_out: business_date + 3.days)
  end
  let!(:folio) { create(:booking_folio, hotel: hotel, booking: booking, is_primary: true) }
  let(:code) { create(:transaction_code, hotel: hotel, kind: "charge", category: "other", code: "JETTY") }
  let!(:jetty_fee) do
    create(:hotel_extra_charge, hotel: hotel, transaction_code: code, pricing_type: "fixed", rate_value: 10,
      charging_unit: "per_person", allow_amount_override: false, auto_apply: true)
  end

  before { create(:booking_room, booking: booking) }

  it "schedules a per-person charge once, on the first night" do
    result = described_class.call(booking: booking)

    expect(result).to be_success
    expect(result.forecasts.size).to eq(1)
    expect(result.forecasts.first.stay_date).to eq(business_date + 1.day)
    expect(result.forecasts.first.amount).to eq(20.to_d)
  end

  it "counts children only when the charge includes them" do
    booking.update!(adults: 2, children: 1)

    expect(described_class.call(booking: booking).forecasts.first.amount).to eq(30.to_d)

    other = create(:booking, hotel: hotel, status: "confirmed", adults: 2, children: 1,
      check_in: business_date + 1.day, check_out: business_date + 3.days)
    create(:booking_folio, hotel: hotel, booking: other, is_primary: true)
    create(:booking_room, booking: other)
    jetty_fee.update!(charge_children: false)

    expect(described_class.call(booking: other).forecasts.first.amount).to eq(20.to_d)
  end

  it "skips charges that are not marked auto apply" do
    jetty_fee.update!(auto_apply: false)

    expect(described_class.call(booking: booking).forecasts).to be_empty
  end

  it "skips inactive charges" do
    code.update!(active: false)

    expect(described_class.call(booking: booking).forecasts).to be_empty
  end

  it "does nothing when the booking has no folio" do
    other = create(:booking, hotel: hotel, status: "confirmed")

    expect(described_class.call(booking: other).forecasts).to be_empty
  end
end
