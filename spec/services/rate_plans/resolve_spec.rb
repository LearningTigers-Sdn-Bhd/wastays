# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePlans::Resolve do
  let(:hotel) { create(:hotel, default_currency: "MYR") }

  it "resolves a selected active custom plan scoped to the hotel" do
    plan = create(:rate_plan, :custom, hotel: hotel)

    result = described_class.call(hotel: hotel, rate_plan_id: plan.id, rate_plan_name: "Ignored")

    expect(result).to be_success
    expect(result.rate_plan).to eq(plan)
    expect(result).not_to be_created
  end

  it "rejects a selected plan from another hotel or a protected plan" do
    other_plan = create(:rate_plan, :custom)
    standard = create(:room_type, hotel: hotel).standard_rate_plan

    cross_hotel = described_class.call(hotel: hotel, rate_plan_id: other_plan.id, rate_plan_name: other_plan.name)
    protected_plan = described_class.call(hotel: hotel, rate_plan_id: standard.id, rate_plan_name: standard.name)

    expect(cross_hotel).not_to be_success
    expect(protected_plan).not_to be_success
  end

  it "normalizes whitespace and case when resolving a typed name" do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Year End Promo")

    result = described_class.call(hotel: hotel, rate_plan_name: "  year   END promo ")

    expect(result).to be_success
    expect(result.rate_plan).to eq(plan)
    expect(result).not_to be_created
  end

  it "creates a minimal custom plan and applies create attributes only on creation" do
    result = described_class.call(
      hotel: hotel,
      rate_plan_name: "  Weekend   Escape ",
      create_attributes: { description: "Two-night offer", base_occupancy: 3, kind: "standard" }
    )

    expect(result).to be_success
    expect(result).to be_created
    expect(result.rate_plan).to have_attributes(
      name: "Weekend Escape",
      description: "Two-night offer",
      base_occupancy: 3,
      kind: "custom",
      currency: "MYR"
    )
  end

  it "does not overwrite shared attributes when an existing plan is resolved" do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Breakfast", description: "Original")

    result = described_class.call(
      hotel: hotel,
      rate_plan_name: "breakfast",
      create_attributes: { description: "Replacement" }
    )

    expect(result).to be_success
    expect(plan.reload.description).to eq("Original")
  end

  it "rejects ambiguous legacy names instead of choosing one" do
    create(:rate_plan, :custom, hotel: hotel, name: "Breakfast")
    create(:rate_plan, :custom, hotel: hotel, name: " breakfast ")

    result = described_class.call(hotel: hotel, rate_plan_name: "BREAKFAST")

    expect(result).not_to be_success
    expect(result.error).to include("More than one rate plan")
  end

  it "does not resolve archived custom plans" do
    plan = create(:rate_plan, :custom, hotel: hotel, name: "Old Promo", archived_at: Time.current)

    result = described_class.call(hotel: hotel, rate_plan_id: plan.id, rate_plan_name: plan.name)

    expect(result).not_to be_success
  end
end
