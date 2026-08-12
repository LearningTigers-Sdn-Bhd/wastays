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

  it "inherits the Standard room child amount for a derived plan" do
    pax_room = create(:room_type, hotel: pax_hotel, base_price: 100)
    standard_plan = pax_room.standard_rate_plan
    standard_band = create(:rate_plan_age_band, rate_plan: standard_plan, min_age: 0, max_age: 12,
                                                pricing_mode: "amount", price_value: 0)
    standard_assignment = pax_room.room_type_rate_plans.find_by!(rate_plan: standard_plan)
    standard_assignment.age_band_prices.create!(rate_plan_age_band: standard_band, price: 35)
    derived_plan = create(:rate_plan, :custom, hotel: pax_hotel)
    derived_band = create(:rate_plan_age_band, rate_plan: derived_plan, min_age: 0, max_age: 12,
                                               pricing_mode: "amount", price_value: 0)
    assignment = create(:room_type_rate_plan, room_type: pax_room, rate_plan: derived_plan,
                                              pricing_mode: "multiplier", pricing_value: -10)

    total = described_class.call(base_nightly_rate: 100.to_d, rate: nil, rate_plan: derived_plan,
                                 adults: 1, children: 1, child_ages: [ 8 ], assignment: assignment)

    expect(derived_band).to be_present
    expect(total).to eq(135)
  end

  it "prefers per-date RoomRate overrides over rate_plan defaults" do
    rate_plan = create(:rate_plan, hotel: hotel, base_occupancy: 2, extra_pax_charge: 25)
    rate = create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current, price: 150, base_occupancy: 3, extra_pax_charge: 10)

    total = described_class.call(base_nightly_rate: 150.to_d, rate: rate, rate_plan: rate_plan, adults: 3, children: 0)
    expect(total).to eq(150) # base_occupancy override (3) covers 3 adults, no extra charge
  end

  # A plan covers many room categories, so what a suite includes and what a
  # single includes belong to the pairing rather than to the plan.
  describe "per-pairing occupancy rules" do
    it "prefers the assignment's rule over the plan's" do
      rate_plan = create(:rate_plan, hotel: hotel, base_occupancy: 2, extra_pax_charge: 25)
      assignment = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan,
                          base_occupancy: 4, extra_pax_charge: 10)

      total = described_class.call(base_nightly_rate: 150.to_d, rate: nil, rate_plan: rate_plan,
                                   adults: 3, children: 0, assignment: assignment)
      expect(total).to eq(150) # the pairing includes 4 pax, so a third adult costs nothing
    end

    it "falls back to the plan when the pairing says nothing" do
      rate_plan = create(:rate_plan, hotel: hotel, base_occupancy: 2, extra_pax_charge: 25)
      assignment = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan)

      total = described_class.call(base_nightly_rate: 150.to_d, rate: nil, rate_plan: rate_plan,
                                   adults: 3, children: 0, assignment: assignment)
      expect(total).to eq(175)
    end

    it "still lets a dated override win over the pairing" do
      rate_plan = create(:rate_plan, hotel: hotel, base_occupancy: 2, extra_pax_charge: 25)
      assignment = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, base_occupancy: 4)
      rate = create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: Date.current,
                    price: 150, base_occupancy: 2, extra_pax_charge: 5)

      total = described_class.call(base_nightly_rate: 150.to_d, rate: rate, rate_plan: rate_plan,
                                   adults: 3, children: 0, assignment: assignment)
      expect(total).to eq(155)
    end

    it "narrows the single supplement per pairing too" do
      rate_plan = create(:rate_plan, hotel: pax_hotel, single_supplement: 30)
      pax_room = create(:room_type, hotel: pax_hotel, base_price: 100)
      assignment = create(:room_type_rate_plan, room_type: pax_room, rate_plan: rate_plan, single_supplement: 50)

      total = described_class.call(base_nightly_rate: 100.to_d, rate: nil, rate_plan: rate_plan,
                                   adults: 1, children: 0, assignment: assignment)
      expect(total).to eq(150)
    end
  end
end
