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
    let(:rate_plan) { create(:rate_plan, hotel: hotel, sell_mode: "per_person") }
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

    context "with child and infant multipliers" do
      subject { described_class.new(room_type: room_type, check_in: check_in, check_out: check_out, rate_plan: rate_plan, adults: 2, children: 1, infants: 1) }

      it "calculates correct rates using multipliers" do
        rate_plan.update!(child_price_multiplier: 0.5, infant_price_multiplier: 0.1)
        expect(subject.call).to eq(520) # (2 * 100 + 1 * 50 + 1 * 10) * 2 nights
      end
    end
  end

  context "with per_room sell mode and extra guest charges" do
    let(:rate_plan) { create(:rate_plan, hotel: hotel, sell_mode: "per_room", base_occupancy: 2, extra_pax_charge: 30.0) }

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
