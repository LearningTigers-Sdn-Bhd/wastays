require "rails_helper"

RSpec.describe Hotel, "plan gating", type: :model do
  let(:group) { create(:feature_group) }
  let(:plan)  { create(:plan) }
  let(:hotel) { create(:hotel, plan: plan) }

  def feature(slug, **opts)
    create(:feature, feature_group: group, slug: slug, **opts)
  end

  describe "#feature_enabled?" do
    it "true when plan_feature enabled" do
      f = feature("housekeeping_flow")
      create(:plan_feature, plan: plan, feature: f, enabled: true)
      expect(hotel.feature_enabled?("housekeeping_flow")).to be true
    end

    it "false when plan_feature disabled" do
      f = feature("housekeeping_flow")
      create(:plan_feature, plan: plan, feature: f, enabled: false)
      expect(hotel.feature_enabled?("housekeeping_flow")).to be false
    end

    it "false when no plan_feature row" do
      feature("housekeeping_flow")
      expect(hotel.feature_enabled?("housekeeping_flow")).to be false
    end

    it "false for unknown slug" do
      expect(hotel.feature_enabled?("nonexistent")).to be false
    end

    it "false when hotel has no plan" do
      f = feature("housekeeping_flow")
      create(:plan_feature, plan: plan, feature: f, enabled: true)
      no_plan = create(:hotel, plan: nil)
      expect(no_plan.feature_enabled?("housekeeping_flow")).to be false
    end
  end

  describe "#feature_level" do
    it "returns level when enabled" do
      f = feature("front_desk", leveled: true)
      create(:plan_feature, plan: plan, feature: f, enabled: true, level: "advanced")
      expect(hotel.feature_level("front_desk")).to eq("advanced")
    end

    it "returns nil when disabled even if level set" do
      f = feature("front_desk", leveled: true)
      create(:plan_feature, plan: plan, feature: f, enabled: false, level: "advanced")
      expect(hotel.feature_level("front_desk")).to be_nil
    end

    it "returns nil for nil-plan hotel" do
      expect(create(:hotel, plan: nil).feature_level("front_desk")).to be_nil
    end
  end

  describe "#feature_addon?" do
    it "true when addon cell set" do
      f = feature("e_invoice", addon: true)
      create(:plan_feature, plan: plan, feature: f, enabled: false, addon: true)
      expect(hotel.feature_addon?("e_invoice")).to be true
    end

    it "false for unknown slug" do
      expect(hotel.feature_addon?("nope")).to be false
    end
  end
end
