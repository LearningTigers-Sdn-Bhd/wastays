require "rails_helper"

RSpec.describe NightAudits::Financials::RepairCompletedNightlyCharges do
  it "backs the public completed-audit repair service" do
    expect(NightAudits::RepairCompletedNightlyCharges::Result).to equal(described_class::Result)
  end
end
