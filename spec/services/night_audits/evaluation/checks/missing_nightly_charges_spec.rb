require "rails_helper"

RSpec.describe NightAudits::Evaluation::Checks::MissingNightlyCharges do
  it "is registered only for post-close evaluation" do
    expect(NightAudits::Evaluate::PRE_CLOSE_CHECKS).not_to include(described_class)
    expect(NightAudits::Evaluate::POST_CLOSE_CHECKS).to include(described_class)
  end
end
