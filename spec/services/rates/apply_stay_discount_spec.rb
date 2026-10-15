# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rates::ApplyStayDiscount do
  let(:rate_plan) { create(:rate_plan, :custom) }

  def rule(**attributes)
    rate_plan.rate_plan_stay_discounts.create!({ discount_type: "percent", from_night: 1 }.merge(attributes))
  end

  describe ".amounts" do
    it "leaves a stay shorter than every rule at the normal rate" do
      rule(min_nights: 3, value: 20)

      expect(described_class.amounts(rate_plan: rate_plan, amounts: [ 100, 100 ])).to eq([ 100, 100 ])
    end

    it "discounts every night once the stay qualifies" do
      rule(min_nights: 2, value: 20)

      expect(described_class.amounts(rate_plan: rate_plan, amounts: [ 100, 100, 100 ])).to eq([ 80, 80, 80 ])
    end

    it "keeps the nights before from_night at full price" do
      rule(min_nights: 2, value: 20, from_night: 2)

      expect(described_class.amounts(rate_plan: rate_plan, amounts: [ 100, 100, 100 ])).to eq([ 100, 80, 80 ])
    end

    it "applies the longest rule the stay qualifies for" do
      rule(min_nights: 2, value: 10)
      rule(min_nights: 4, value: 30)

      expect(described_class.amounts(rate_plan: rate_plan, amounts: [ 100, 100, 100 ])).to eq([ 90, 90, 90 ])
      expect(described_class.amounts(rate_plan: rate_plan, amounts: [ 100, 100, 100, 100 ]).uniq).to eq([ 70 ])
    end

    it "takes an amount off per guest, never below zero" do
      rule(min_nights: 2, discount_type: "amount", value: 30)

      expect(described_class.amounts(rate_plan: rate_plan, amounts: [ 200, 50 ], guests: 2)).to eq([ 140, 0 ])
    end
  end

  describe ".snapshot" do
    let(:snapshot) do
      { "2026-10-02" => { "price" => "100.0" }, "2026-10-01" => { "price" => "100.0" } }
    end

    it "discounts nights in date order and records what it did" do
      rule(min_nights: 2, value: 25, from_night: 2)

      result = described_class.snapshot(rate_plan: rate_plan, snapshot: snapshot)

      expect(result["2026-10-01"]["price"]).to eq("100.0")
      expect(result["2026-10-02"]).to include("price" => "75.0", "undiscounted_price" => "100.0")
      expect(result["2026-10-02"]["stay_discount"]).to include("min_nights" => 2, "discount_type" => "percent")
    end

    it "never discounts a night twice" do
      rule(min_nights: 2, value: 25)

      once = described_class.snapshot(rate_plan: rate_plan, snapshot: snapshot)

      expect(described_class.snapshot(rate_plan: rate_plan, snapshot: once)).to eq(once)
    end
  end
end
