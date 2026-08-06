require "rails_helper"

RSpec.describe PlanFeature, type: :model do
  it { is_expected.to belong_to(:plan) }
  it { is_expected.to belong_to(:feature) }

  it "rejects duplicate feature per plan" do
    plan = create(:plan)
    feature = create(:feature)
    create(:plan_feature, plan: plan, feature: feature)
    dup = build(:plan_feature, plan: plan, feature: feature)
    expect(dup).not_to be_valid
  end

  it "rejects invalid level" do
    expect(build(:plan_feature, level: "bogus")).not_to be_valid
  end

  it "allows nil level" do
    expect(build(:plan_feature, level: nil)).to be_valid
  end
end
