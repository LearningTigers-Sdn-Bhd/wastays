require "rails_helper"

RSpec.describe NightAudits::Processing::DetectMissedArrivals do
  it "backs the public missed-arrival detector" do
    audit = create(:night_audit)

    expect(described_class.call(night_audit: audit, user: nil).success?).to be(true)
  end
end
