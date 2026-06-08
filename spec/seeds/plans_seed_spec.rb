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

  it "sets front desk levels correctly" do
    feature = Feature.find_by(slug: "front_desk_operations")
    levels = PlanFeature.where(feature: feature).joins(:plan).pluck("plans.slug", :level).to_h
    expect(levels["direct"]).to eq("manual")
    expect(levels["core"]).to eq("basic")
    expect(levels["plus"]).to eq("basic")
    expect(levels["enterprise"]).to eq("advanced")
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
