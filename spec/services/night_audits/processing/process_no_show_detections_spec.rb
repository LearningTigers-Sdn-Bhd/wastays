require "rails_helper"

RSpec.describe NightAudits::Processing::ProcessNoShowDetections do
  it "backs the public no-show processor" do
    audit = create(:night_audit)

    expect(described_class.call(night_audit: audit, user: nil).success?).to be(true)
  end
end
