require "rails_helper"

RSpec.describe Concierge::ConciergeUrl do
  let(:hotel) { build(:hotel, slug: "sample-hotel") }

  it "returns the canonical concierge URL" do
    url = described_class.for(hotel, host: "wastays.com", scheme: "https")
    expect(url).to eq("https://wastays.com/concierge/sample-hotel")
  end

  it "supports custom scheme and host" do
    url = described_class.for(hotel, host: "localhost:3000", scheme: "http")
    expect(url).to eq("http://localhost:3000/concierge/sample-hotel")
  end
end
