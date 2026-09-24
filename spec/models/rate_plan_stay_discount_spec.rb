# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePlanStayDiscount do
  let(:rate_plan) { create(:rate_plan, :custom) }

  it "rejects a one-night minimum, a percent above 100 and a start night past the minimum" do
    discount = rate_plan.rate_plan_stay_discounts.build(min_nights: 1, discount_type: "percent", value: 120, from_night: 3)

    expect(discount).not_to be_valid
    expect(discount.errors.attribute_names).to include(:min_nights, :value)

    discount.assign_attributes(min_nights: 2)
    expect(discount).not_to be_valid
    expect(discount.errors[:from_night]).to include("must be within the 2-night minimum")
  end

  it "allows one rule per minimum stay" do
    rate_plan.rate_plan_stay_discounts.create!(min_nights: 3, discount_type: "percent", value: 10)

    duplicate = rate_plan.rate_plan_stay_discounts.build(min_nights: 3, discount_type: "amount", value: 20)
    expect(duplicate).not_to be_valid
  end

  it "describes itself for the editor" do
    discount = rate_plan.rate_plan_stay_discounts.build(min_nights: 3, discount_type: "percent", value: 15, from_night: 2)

    expect(discount.summary(currency: "MYR")).to eq("Stay 3+ nights: 15% off, from night 2")
  end
end
