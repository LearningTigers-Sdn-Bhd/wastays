# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::NightlyPaxPrice do
  let(:hotel) { create(:hotel) }
  # Per-person plans only exist at a per-person property — the plan inherits
  # the mode, so the two cases need two hotels.
  let(:pax_hotel) { create(:hotel, :per_person) }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 100) }

  it "computes flat per-room price when rate_plan is nil" do
    total = described_class.call(base_nightly_rate: 100.to_d, rate: nil, rate_plan: nil, adults: 2, children: 0)
    expect(total).to eq(100)
  end

  it "adds extra_pax_charge for per-room plans once billable pax exceeds base_occupancy" do
    rate_plan = create(:rate_plan, hotel: hotel, base_occupancy: 2, extra_pax_charge: 25)

    total = described_class.call(base_nightly_rate: 150.to_d, rate: nil, rate_plan: rate_plan, adults: 3, children: 0)
    expect(total).to eq(175) # 150 + (1 extra guest * 25)
  end

  it "multiplies adults and children by the nightly rate for per_person plans" do
    rate_plan = create(:rate_plan, hotel: pax_hotel, child_price_multiplier: 0.5)

    total = described_class.call(base_nightly_rate: 100.to_d, rate: nil, rate_plan: rate_plan, adults: 2, children: 1)
    expect(total).to eq(250) # (2 * 100) + (1 * 100 * 0.5)
  end

  it "adds the single supplement for single-occupancy per_person bookings" do
    rate_plan = create(:rate_plan, hotel: pax_hotel, single_supplement: 30)

    total = described_class.call(base_nightly_rate: 100.to_d, rate: nil, rate_plan: rate_plan, adults: 1, children: 0)
    expect(total).to eq(130)
  end

  it "prices children using age bands when child_ages are supplied" do
    rate_plan = create(:rate_plan, :age_banded, hotel: pax_hotel)

    total = described_class.call(base_nightly_rate: 100.to_d, rate: nil, rate_plan: rate_plan, adults: 1, children: 2, child_ages: [ 8, 15 ])
    # 1 adult * 100 + band(4-11)=40 + band(12-17)=20
    expect(total).to eq(160)
  end

  it "prefers per-date RoomRate overrides over rate_plan defaults" do
    rate_plan = create(:rate_plan, hotel: hotel, base_occupancy: 2, extra_pax_charge: 25)
    rate = create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 150, base_occupancy: 3, extra_pax_charge: 10)

    total = described_class.call(base_nightly_rate: 150.to_d, rate: rate, rate_plan: rate_plan, adults: 3, children: 0)
    expect(total).to eq(150) # base_occupancy override (3) covers 3 adults, no extra charge
  end
end
