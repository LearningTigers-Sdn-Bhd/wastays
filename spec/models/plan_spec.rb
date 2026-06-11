require "rails_helper"

RSpec.describe Plan, type: :model do
  it { is_expected.to have_many(:plan_features).dependent(:destroy) }
  it { is_expected.to have_many(:features).through(:plan_features) }
  it { is_expected.to validate_presence_of(:name) }

  it "generates slug from name on create" do
    plan = Plan.create!(name: "Plus Tier")
    expect(plan.slug).to eq("plus-tier")
  end

  it "enforces unique slug" do
    create(:plan, slug: "plus")
    dup = build(:plan, slug: "plus")
    expect(dup).not_to be_valid
  end
end
