require "rails_helper"

RSpec.describe "plans seed", type: :model do
  before { load Rails.root.join("db", "seeds", "plans.rb") }

  it "creates the 5 plans with Plus renamed and flagged popular" do
    expect(Plan.pluck(:slug)).to match_array(%w[easy direct core plus enterprise])
    expect(Plan.find_by(slug: "plus").most_popular).to be true
    expect(Plan.where(name: "Pro")).to be_empty
  end

  it "enables AIC base flows on all plans" do
    feature = Feature.find_by(slug: "whatsapp_automation_flows")
    slugs = PlanFeature.where(feature: feature, enabled: true).joins(:plan).pluck("plans.slug")
    expect(slugs).to match_array(%w[easy direct core plus enterprise])
  end

  it "restricts channel manager to plus + enterprise" do
    feature = Feature.find_by(slug: "manage_40_otas")
    slugs = PlanFeature.where(feature: feature, enabled: true).joins(:plan).pluck("plans.slug")
    expect(slugs).to match_array(%w[plus enterprise])
  end

  it "puts folio access under booking engine default plans" do
    feature = Feature.find_by(slug: "folio_management_billing")
    slugs = PlanFeature.where(feature: feature, enabled: true).joins(:plan).pluck("plans.slug")
    expect(slugs).to match_array(%w[direct core plus enterprise])
    expect(feature.feature_group.slug).to eq("be")
  end

  it "sets front desk levels correctly" do
    feature = Feature.find_by(slug: "front_desk_operations")
    levels = PlanFeature.where(feature: feature).joins(:plan).pluck("plans.slug", :level).to_h
    expect(levels["direct"]).to be_nil
    expect(levels["core"]).to eq("basic")
    expect(levels["plus"]).to eq("basic")
    expect(levels["enterprise"]).to eq("advanced")
  end

  it "does not include manual PMS and rate rows for direct plan" do
    expectation_map = {
      "reservation_management" => nil,
      "room_management_availability" => nil,
      "front_desk_operations" => nil,
      "rate_plan_hierarchy" => nil,
      "date_range_dow_pricing" => nil
    }

    expectation_map.each do |slug, expected_level|
      feature = Feature.find_by(slug: slug)
      plan_feature = PlanFeature.joins(:plan).find_by(feature: feature, plans: { slug: "direct" })

      expect(plan_feature).to be_nil, "expected no direct plan row for #{slug}"
    end
  end

  it "marks add-ons as addon cells, not enabled" do
    feature = Feature.find_by(slug: "live_chat")
    pf = PlanFeature.find_by(feature: feature, plan: Plan.find_by(slug: "easy"))
    expect(pf.addon).to be true
    expect(pf.enabled).to be false
  end

  it "is idempotent" do
    before_count = PlanFeature.count
    load Rails.root.join("db", "seeds", "plans.rb")
    expect(PlanFeature.count).to eq(before_count)
  end
end
