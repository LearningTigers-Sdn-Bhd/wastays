# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rates::ResolveEffectiveNightlyPrice do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 100) }
  let(:standard_plan) { room_type.standard_rate_plan }
  let(:rate_plan) { create(:rate_plan, :custom, hotel: hotel, name: "Flexible") }
  let(:date) { Date.current }

  subject(:result) do
    described_class.call(
      room_type: room_type,
      rate_plan: rate_plan,
      date: date,
      adults: 2,
      children: 0
    )
  end

  it "uses an explicit daily plan price before every fallback" do
    create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "offset", pricing_value: 25)
    explicit = create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: date, price: 80)
    create(:room_rate, room_type: room_type, rate_plan: standard_plan, date: date, price: 150)

    expect(result).to have_attributes(amount: 80.to_d, base_amount: 80.to_d, source: :daily_override, room_rate: explicit)
  end

  it "uses a fixed assignment's persisted starting price" do
    create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "fixed", pricing_value: 125)

    expect(result).to have_attributes(amount: 125.to_d, base_amount: 125.to_d, source: :starting_price, room_rate: nil)
  end

  it "keeps legacy fixed assignments with no starting price on the room default" do
    create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "fixed", pricing_value: nil)
    create(:room_rate, room_type: room_type, rate_plan: standard_plan, date: date, price: 180)

    expect(result).to have_attributes(amount: 100.to_d, source: :room_category_default)
  end

  it "derives a percentage adjustment from that date's Standard Rate" do
    create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "multiplier", pricing_value: -10)
    anchor = create(:room_rate, room_type: room_type, rate_plan: standard_plan, date: date, price: 200)

    expect(result).to have_attributes(amount: 180.to_d, base_amount: 180.to_d, source: :standard_daily_rate, room_rate: anchor)
  end

  it "derives an amount adjustment from the room default when the date has no Standard Rate" do
    create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "offset", pricing_value: 35)

    expect(result).to have_attributes(amount: 135.to_d, source: :room_category_default)
  end

  it "floors a negative derived price at zero" do
    create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "offset", pricing_value: -150)

    expect(result.amount).to eq(0.to_d)
  end

  it "reads a legacy unattributed row as the Standard Rate anchor" do
    legacy = create(:room_rate, room_type: room_type, rate_plan: nil, date: date, price: 175)

    expect(result).to have_attributes(amount: 175.to_d, source: :standard_daily_rate, room_rate: legacy)
  end

  it "does not use a daily row from another currency" do
    create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: date, price: 999, currency: "USD")

    expect(result).to have_attributes(amount: 100.to_d, currency: "MYR")
  end

  it "uses a real Corporate plan price" do
    corporate_plan = room_type.corporate_rate_plan
    rate = create(:room_rate, room_type: room_type, rate_plan: corporate_plan, date: date, price: 120)

    tier_result = described_class.call(room_type: room_type, rate_plan: corporate_plan, date: date)

    expect(tier_result).to have_attributes(amount: 120.to_d, base_amount: 120.to_d, source: :daily_override, room_rate: rate)
  end

  context "when the property charges one price per room" do
    it "adds the plan's extra guest charge above the included guests" do
      rate_plan.update!(base_occupancy: 2, extra_pax_charge: 30)

      occupied = described_class.call(room_type: room_type, rate_plan: rate_plan, date: date, adults: 3)

      expect(occupied).to have_attributes(base_amount: 100.to_d, amount: 130.to_d)
    end

    it "uses an explicit daily occupancy override only for that plan" do
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: date, price: 100, base_occupancy: 2, extra_pax_charge: 45)

      occupied = described_class.call(room_type: room_type, rate_plan: rate_plan, date: date, adults: 3)

      expect(occupied.amount).to eq(145.to_d)
    end
  end

  context "when the property charges per guest" do
    let(:hotel) { create(:hotel, :per_person, default_currency: "MYR") }

    it "prices adults, age-banded children, and the one-guest surcharge" do
      rate_plan.update!(single_supplement: 20, child_price_multiplier: 0.5)
      create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 6, max_age: 12, pricing_mode: "multiplier", price_value: 25)

      family = described_class.call(room_type: room_type, rate_plan: rate_plan, date: date, adults: 2, children: 1, child_ages: [ 8 ])
      single = described_class.call(room_type: room_type, rate_plan: rate_plan, date: date, adults: 1)

      expect(family).to have_attributes(base_amount: 100.to_d, amount: 225.to_d)
      expect(single.amount).to eq(120.to_d)
    end


    it "uses independent starting prices for each adult occupancy" do
      room_type.update!(max_adults: 2)
      assignment = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "fixed")
      assignment.occupancy_prices.create!(adults: 1, price: 180)
      assignment.occupancy_prices.create!(adults: 2, price: 300)

      single = described_class.call(room_type: room_type, rate_plan: rate_plan, date: date, adults: 1)
      double = described_class.call(room_type: room_type, rate_plan: rate_plan, date: date, adults: 2)

      expect(single).to have_attributes(amount: 180.to_d, base_amount: 180.to_d)
      expect(double).to have_attributes(amount: 300.to_d, base_amount: 300.to_d)
    end

    it "prices a room child percentage from the one-adult rung" do
      room_type.update!(max_adults: 2, max_children: 1)
      assignment = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "fixed")
      assignment.occupancy_prices.create!(adults: 1, price: 100)
      assignment.occupancy_prices.create!(adults: 2, price: 300)
      band = create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 0, max_age: 12,
                                         pricing_mode: "multiplier", price_value: 0)
      assignment.age_band_prices.create!(rate_plan_age_band: band, price: 50)

      family = described_class.call(
        room_type: room_type, rate_plan: rate_plan, date: date,
        adults: 2, children: 1, child_ages: [ 8 ]
      )

      # Adult room total 300 + 50% of the one-adult rung (100).
      expect(family.amount).to eq(350.to_d)
    end

    it "lets a date-specific occupancy price override only that occupancy" do
      room_type.update!(max_adults: 2)
      assignment = create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "fixed")
      assignment.occupancy_prices.create!(adults: 1, price: 180)
      assignment.occupancy_prices.create!(adults: 2, price: 300)
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: date, price: 300, occupancy_prices: { "1" => 210 })

      single = described_class.call(room_type: room_type, rate_plan: rate_plan, date: date, adults: 1)
      double = described_class.call(room_type: room_type, rate_plan: rate_plan, date: date, adults: 2)

      expect(single.amount).to eq(210.to_d)
      expect(double.amount).to eq(300.to_d)
    end
  end

  it "uses supplied preloaded rates and assignment without querying their associations" do
    assignment = build(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "offset", pricing_value: 10)
    anchor = build(:room_rate, room_type: room_type, rate_plan: standard_plan, date: date, price: 140, currency: "MYR")

    allow(room_type).to receive(:room_rates).and_raise("queried rates")
    allow(room_type).to receive(:room_type_rate_plans).and_raise("queried assignments")

    preloaded = described_class.call(
      room_type: room_type,
      rate_plan: rate_plan,
      date: date,
      room_rates: [ anchor ],
      room_type_rate_plan: assignment
    )

    expect(preloaded.amount).to eq(150.to_d)
  end
end
