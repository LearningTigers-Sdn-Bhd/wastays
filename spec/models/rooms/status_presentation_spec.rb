# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::StatusPresentation do
  # The board's status filter, its badges and its exports are all built from
  # RESOLVED_STATUSES, so a status the resolver can return but this module has
  # never heard of would be unfilterable and would render as a neutral badge.
  it "covers every status Rooms::StatusResolver can resolve to, and nothing else" do
    resolvable = RoomStatus::STATUSES + [ "occupied" ]

    expect(described_class::RESOLVED_STATUSES).to match_array(resolvable)
  end

  it "gives each of them a badge variant of its own" do
    expect(described_class::BADGE_VARIANTS.keys.map(&:to_s)).to match_array(described_class::RESOLVED_STATUSES)
    expect(described_class.badge_variant("occupied")).to eq(:accent)
  end

  it "falls back to a neutral badge for anything it does not know" do
    expect(described_class.badge_variant("something_else")).to eq(:neutral)
  end

  it "writes a status the way the board reads it" do
    expect(described_class.label("awaiting_inspection")).to eq("Awaiting Inspection")
    expect(described_class.label(:out_of_service)).to eq("Out of Service")
  end
end
