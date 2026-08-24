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
end
