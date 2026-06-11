require "rails_helper"

RSpec.describe FeatureGroup, type: :model do
  it { is_expected.to have_many(:features).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:name) }

  it "generates slug from name" do
    expect(FeatureGroup.create!(name: "AI Concierge (AIC)").slug).to eq("ai-concierge-aic")
  end
end
