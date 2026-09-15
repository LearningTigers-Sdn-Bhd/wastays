require "rails_helper"

RSpec.describe Concierge::ConciergeUrl do
  let(:public_id) { "550e8400-e29b-41d4-a716-446655440000" }
  let(:hotel) { build(:hotel, unique_id: "10101", public_id:, slug: "sample-hotel") }

  it "returns the canonical concierge URL" do
    url = described_class.for(hotel, host: "wastays.com", scheme: "https")
    expect(url).to eq("https://wastays.com/concierge/10101/#{public_id}")
  end

  it "supports custom scheme and host" do
    url = described_class.for(hotel, host: "localhost:3000", scheme: "http")
    expect(url).to eq("http://localhost:3000/concierge/10101/#{public_id}")
  end
end
