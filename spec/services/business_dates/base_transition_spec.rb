require "rails_helper"

RSpec.describe BusinessDates::BaseTransition do
  it "is exercised through concrete business-date transition services" do
    expect(described_class::MANAGE_PERMISSION).to eq("manage_night_audit")
  end
end
