require "rails_helper"

RSpec.describe NightAudits::Processing::DetectDueOuts do
  it "backs the public due-out detector" do
    expect(NightAudits::DetectDueOuts::Result).to equal(described_class::Result)
  end
end
