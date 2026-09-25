# frozen_string_literal: true

require "rails_helper"

RSpec.describe Attractions::FindDuplicate do
  it "prefers an approved record when inactive records share the fingerprint" do
    approved = create(:attraction)
    create(
      :attraction,
      :archived,
      name: approved.name,
      latitude: approved.latitude,
      longitude: approved.longitude,
      coordinate_fingerprint: approved.coordinate_fingerprint
    )

    expect(described_class.call(fingerprint: approved.coordinate_fingerprint)).to eq(approved)
  end

  it "finds an approved record by the same URL when its stored name differs" do
    existing = create(:attraction, name: "Imago Mall")
    parsed = Attractions::GoogleMapsUrlParser.call(existing.google_maps_url).parsed
    existing.update!(name: "Imago Shopping Mall")

    expect(described_class.call(fingerprint: parsed.fingerprint, google_maps_url: parsed.google_maps_url)).to eq(existing)
  end
end
