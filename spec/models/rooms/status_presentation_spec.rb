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

  # Three pairs of statuses share a badge variant (cleaning/awaiting_inspection,
  # inspection_failed/out_of_service, dirty/late_checkout_detected), so hue alone
  # cannot separate them and the icon has to.
  it "gives each status an icon of its own" do
    expect(described_class::ICONS.keys.map(&:to_s)).to match_array(described_class::RESOLVED_STATUSES)
    expect(described_class::ICONS.values.uniq.length).to eq(described_class::ICONS.length)
  end

  it "separates the statuses that share a badge variant by icon" do
    described_class::BADGE_VARIANTS.group_by { |_status, variant| variant }.each_value do |pairs|
      icons = pairs.map { |status, _| described_class.icon(status) }
      expect(icons.uniq.length).to eq(icons.length)
    end
  end

  it "falls back to a known icon for anything it does not know" do
    expect(described_class.icon("something_else")).to eq(described_class::UNKNOWN_ICON)
  end

  it "treats only a ready room as assignable" do
    expect(described_class.assignable?("ready")).to be(true)
    expect(described_class.assignable?("dirty")).to be(false)
    expect(described_class.assignable?("awaiting_inspection")).to be(false)
  end

  it "falls back to a neutral badge for anything it does not know" do
    expect(described_class.badge_variant("something_else")).to eq(:neutral)
  end

  it "writes a status the way the board reads it" do
    expect(described_class.label("awaiting_inspection")).to eq("Awaiting Inspection")
    expect(described_class.label(:out_of_service)).to eq("Out of Service")
  end
end
