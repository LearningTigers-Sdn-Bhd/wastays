require "rails_helper"

RSpec.describe AiConcierge::Matching::RatePlanMatcher do
  let(:rate_plans) do
    [
      { "rate_plan_id" => 1, "name" => "Standard Rate", "total_price" => 300 },
      { "rate_plan_id" => 2, "name" => "Non-Refundable Rate", "total_price" => 250 },
      { "rate_plan_id" => 3, "name" => "Flexible Rate", "total_price" => 350 }
    ]
  end

  def match(message:, rate_plan_name: nil, plans: rate_plans)
    described_class.new(message: message, rate_plan_name: rate_plan_name, rate_plans: plans).call
  end

  it "matches the unique cheapest rate plan by price intent" do
    expect(match(message: "the cheaper one")).to eq(rate_plans.second)
  end

  it "matches by ordinal language" do
    expect(match(message: "second one")).to eq(rate_plans.second)
  end

  it "distinguishes refundable from non-refundable" do
    refundable_plans = [
      { "name" => "Refundable Rate", "total_price" => 300 },
      { "name" => "Non-Refundable Rate", "total_price" => 250 }
    ]

    expect(match(message: "refundable please", plans: refundable_plans)).to eq(refundable_plans.first)
    expect(match(message: "non refundable please", plans: refundable_plans)).to eq(refundable_plans.second)
  end

  it "does not choose standard when multiple standard plans match" do
    ambiguous = [
      { "name" => "Standard Rate", "total_price" => 300 },
      { "name" => "Standard Breakfast Rate", "total_price" => 330 }
    ]

    expect(match(message: "standard", plans: ambiguous)).to be_nil
  end

  it "matches exact extracted rate plan names" do
    expect(match(message: "", rate_plan_name: "Flexible Rate")).to eq(rate_plans.third)
  end

  it "returns nil for ambiguous partial matches" do
    ambiguous = [
      { "name" => "Flexible Rate", "total_price" => 350 },
      { "name" => "Flexible Breakfast Rate", "total_price" => 380 }
    ]

    expect(match(message: "flexible", plans: ambiguous)).to be_nil
  end
end
