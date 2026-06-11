require "rails_helper"

RSpec.describe PlanFeaturesHelper, type: :helper do
  let(:group) { create(:feature_group) }
  let(:plan)  { create(:plan) }
  let(:hotel) { create(:hotel, plan: plan) }

  before { helper.define_singleton_method(:current_user) { nil } }

  it "true when hotel feature enabled" do
    f = create(:feature, feature_group: group, slug: "ai_concierge_page")
    create(:plan_feature, plan: plan, feature: f, enabled: true)
    expect(helper.feature_enabled_for_hotel?("ai_concierge_page", hotel)).to be true
  end

  it "false when disabled" do
    expect(helper.feature_enabled_for_hotel?("ai_concierge_page", hotel)).to be false
  end
end
