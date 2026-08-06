require "rails_helper"

RSpec.describe NightAudits::Reporting::BuildRunResults do
  it "backs the public run-result builder" do
    audit = create(:night_audit)

    expect(described_class.call(night_audit: audit)).to eq(NightAudits::BuildRunResults.call(night_audit: audit))
  end
end
