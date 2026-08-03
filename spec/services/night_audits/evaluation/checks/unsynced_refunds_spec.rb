require "rails_helper"

RSpec.describe NightAudits::Evaluation::Checks::UnsyncedRefunds do
  it "is registered for every evaluation phase" do
    expect(NightAudits::Evaluate::PRE_CLOSE_CHECKS).to include(described_class)
    expect(NightAudits::Evaluate::POST_CLOSE_CHECKS).to include(described_class)
  end
end
