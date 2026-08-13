require "rails_helper"

RSpec.describe Concierge::ConciergeUrl do
  # A QR code printed and stuck on a wall outlives any rename, so the URL has to
  # carry the immutable code rather than the name-derived slug.
  let(:hotel) { build(:hotel, unique_id: "H7K2M", slug: "sample-hotel") }

  it "returns the canonical concierge URL" do
    url = described_class.for(hotel, host: "wastays.com", scheme: "https")
    expect(url).to eq("https://wastays.com/concierge/H7K2M")
  end

  it "supports custom scheme and host" do
    url = described_class.for(hotel, host: "localhost:3000", scheme: "http")
    expect(url).to eq("http://localhost:3000/concierge/H7K2M")
  end
end
