# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::CalculateStayPrice do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 100) }
  let(:check_in) { Date.current }
  let(:check_out) { Date.current + 2.days }

  subject { described_class.new(room_type: room_type, check_in: check_in, check_out: check_out) }

  it "calculates total price using base price when no rates exist" do
    expect(subject.call).to eq(200) # 100 * 2 nights
  end

  it "uses custom rates when they exist" do
    create(:room_rate, room_type: room_type, date: check_in, price: 150)
    expect(subject.call).to eq(250) # 150 (night 1) + 100 (night 2)
  end

  it "returns 0 if room_type is nil" do
    service = described_class.new(room_type: nil, check_in: check_in, check_out: check_out)
    expect(service.call).to eq(0)
  end

  it "returns 0 if check_in is nil" do
    service = described_class.new(room_type: room_type, check_in: nil, check_out: check_out)
    expect(service.call).to eq(0)
  end

  context "with per_person sell mode" do
    # Rate plans inherit the mode from their hotel, so a per-person plan means
    # a per-person property.
    let(:hotel) { create(:hotel, :per_person) }
    let(:rate_plan) { create(:rate_plan, hotel: hotel) }
    subject { described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, pax: 3) }

    it "multiplies the price by pax" do
      expect(subject.call).to eq(600) # (100 * 3 pax) * 2 nights
    end

    context "when pax is 1 (single occupancy)" do
      subject { described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, pax: 1) }

      it "adds the rate plan single supplement" do
        rate_plan.update!(single_supplement: 25.0)
        expect(subject.call).to eq(250) # (100 * 1 pax + 25 supplement) * 2 nights
      end

      it "prioritizes the room rate single supplement over the rate plan default" do
        rate_plan.update!(single_supplement: 25.0)
        create(:room_rate, room_type: room_type, date: check_in, price: 100, single_supplement: 40.0, rate_plan: rate_plan)
        expect(subject.call).to eq(265) # Night 1: (100 + 40) = 140. Night 2: (100 + 25) = 125. Total = 265.
      end
    end

    context "with child multipliers" do
      subject { described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, adults: 2, children: 1) }

      it "calculates correct rates using multipliers" do
        rate_plan.update!(child_price_multiplier: 0.5)
        expect(subject.call).to eq(500) # (2 * 100 + 1 * 50) * 2 nights
      end
    end

    context "with age-banded child pricing" do
      before do
        rate_plan.update!(child_price_multiplier: 0.6)
        create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 4, max_age: 11, price_value: 40, label: "Child")
        create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 12, max_age: 17, price_value: 20, label: "Teen")
      end

      it "prices a flat-amount band regardless of the nightly rate" do
        create(:rate_plan_age_band, :amount, rate_plan: rate_plan, min_age: 18, max_age: 25, price_value: 15.0, label: "Young Adult")
        service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, adults: 2, children: 1, child_ages: [ 20 ])
        # (2*100 + 15 flat) * 2 nights = 215 * 2 = 430
        expect(service.call).to eq(430)
      end

      it "prices each child individually by their resolved age band" do
        service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, adults: 2, children: 2, child_ages: [ 6, 15 ])
        # (2*100 + 100*0.4 + 100*0.2) * 2 nights = 260 * 2 = 520
        expect(service.call).to eq(520)
      end

      it "falls back to the flat child_price_multiplier when ages are not supplied" do
        service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, adults: 2, children: 2)
        # (2*100 + 2*100*0.6) * 2 nights = 320 * 2 = 640
        expect(service.call).to eq(640)
      end

      it "falls back to the flat child_price_multiplier for an age not covered by any band" do
        service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, adults: 2, children: 1, child_ages: [ 1 ])
        # (2*100 + 100*0.6) * 2 nights = 260 * 2 = 520
        expect(service.call).to eq(520)
      end
    end
  end

  context "with per_room sell mode and extra guest charges" do
    let(:rate_plan) { create(:rate_plan, hotel: hotel, base_occupancy: 2, extra_pax_charge: 30.0) }

    it "does not charge extra if guest count is equal to or less than base occupancy" do
      service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, adults: 2, children: 0)
      expect(service.call).to eq(200) # 100 * 2 nights
    end

    it "adds extra guest charge for guests exceeding base occupancy" do
      service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, adults: 2, children: 1)
      expect(service.call).to eq(260) # (100 + 30 extra) * 2 nights
    end

    it "prioritizes daily rate extra guest charges over rate plan defaults" do
      create(:room_rate, room_type: room_type, date: check_in, price: 100, base_occupancy: 2, extra_pax_charge: 45.0, rate_plan: rate_plan)
      service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, adults: 2, children: 1)
      expect(service.call).to eq(275) # Night 1: 145. Night 2: 130. Total = 275.
    end
  end

  context "with derived room-type pricing" do
    let(:rate_plan) { create(:rate_plan, hotel: hotel, name: "Non-Refundable") }

    it "computes a multiplier off the room type's own Standard Rate price for that date, not the flat base price" do
      standard_plan = room_type.rate_plans.first
      create(:room_rate, room_type: room_type, rate_plan: standard_plan, date: check_in, price: 200)
      create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "multiplier", pricing_value: -10)

      service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan)
      # Night 1: anchor 200 (explicit standard rate) -10% = 180. Night 2: anchor 100 (base_price) -10% = 90.
      expect(service.call).to eq(270)
    end

    it "applies a flat offset off the anchor price" do
      create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "offset", pricing_value: 80)

      service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan)
      expect(service.call).to eq(360) # (100 + 80) * 2 nights
    end

    it "lets an explicit RoomRate for the derived rate plan win over derivation" do
      create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan, pricing_mode: "offset", pricing_value: 80)
      create(:room_rate, room_type: room_type, rate_plan: rate_plan, date: check_in, price: 55)

      service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan)
      expect(service.call).to eq(235) # Night 1 explicit: 55. Night 2 derived: (100 + 80) = 180. Total 235.
    end
  end

  context "with corporate rates" do
    before do
      create(:room_rate, room_type: room_type, date: check_in, price: 100, corporate_price: 80)
      create(:room_rate, room_type: room_type, date: check_in + 1.day, price: 100, corporate_price: 80)
    end

    it "uses corporate price when corporate_rate is true" do
      service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, corporate_rate: true)
      expect(service.call).to eq(160)
    end

    it "uses corporate price when rate_tier is corporate" do
      service = described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_tier: :corporate)
      expect(service.call).to eq(160)
    end
  end
end
