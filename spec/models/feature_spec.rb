require "rails_helper"

RSpec.describe Feature, type: :model do
  it { is_expected.to belong_to(:feature_group) }
  it { is_expected.to have_many(:plan_features).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:name) }

  it "enforces unique slug" do
    create(:feature, slug: "housekeeping_flow")
    expect(build(:feature, slug: "housekeeping_flow")).not_to be_valid
  end
end
