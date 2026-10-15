# frozen_string_literal: true

require "rails_helper"

# Long-stay discounts reach the booking through its nightly rate snapshot, which
# is what the booking total and the folio's nightly charges are read from.
RSpec.describe "Long-stay discount pricing" do
  let(:hotel) { create(:hotel) }
  let(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Villa", room_number_mode: "custom", quantity: 2, base_price: 100.0, max_adults: 2, room_numbers: %w[V1 V2] }
    )
  end
  let(:rate_plan) { room_type.standard_rate_plan }
  let(:check_in) { Date.current + 10 }

  before { rate_plan.rate_plan_stay_discounts.create!(min_nights: 3, discount_type: "percent", value: 20) }

  def snapshot_for(nights, booking: nil)
    Bookings::BuildFinancialSnapshot.new(
      hotel: hotel, booking: booking, room_type: room_type, rate_plan: rate_plan,
      check_in: check_in, check_out: check_in + nights, guest_country: "Malaysia"
    ).call
  end

  it "prices a qualifying stay at the discounted rate" do
    result = snapshot_for(3)

    expect(result.room_total).to eq(240.to_d)
    expect(result.nightly_rate_snapshot.values.map { |night| night["price"] }.uniq).to eq([ "80.0" ])
  end

  it "leaves a shorter stay at the normal rate" do
    expect(snapshot_for(2).room_total).to eq(200.to_d)
  end

  it "keeps an OTA booking at the price the OTA sold it for" do
    booking = create(:booking, hotel: hotel, source: "ota")

    expect(snapshot_for(3, booking: booking).room_total).to eq(300.to_d)
  end

  it "agrees with CalculateStayPrice" do
    price = Bookings::CalculateStayPrice.new(room_type: room_type, check_in: check_in, check_out: check_in + 3, rate_plan: rate_plan).call

    expect(price).to eq(240.to_d)
  end
end
