# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260805120000_add_kind_to_rate_plans")

RSpec.describe AddKindToRatePlans do
  let(:hotel) { create(:hotel) }

  def backfilled_kind(name)
    plan = create(:rate_plan, hotel: hotel, name: name, kind: "custom")
    described_class.new.send(:backfill_kinds)
    plan.reload.kind
  end

  it "maps every name the old string matcher recognised" do
    expect(backfilled_kind("Standard Rate")).to eq("standard")
    expect(backfilled_kind("Walk-in Rate")).to eq("walk_in")
    expect(backfilled_kind("Walk in Rate")).to eq("walk_in")
    expect(backfilled_kind("Walk-in")).to eq("walk_in")
    expect(backfilled_kind("Walk in")).to eq("walk_in")
    expect(backfilled_kind("Corporate Rate")).to eq("corporate")
    expect(backfilled_kind("Corporate")).to eq("corporate")
    expect(backfilled_kind("OTA Rate")).to eq("ota")
    expect(backfilled_kind("OTA")).to eq("ota")
  end

  it "matches case-insensitively and ignores surrounding whitespace, as the matcher did" do
    expect(backfilled_kind("  standard rate  ")).to eq("standard")
    expect(backfilled_kind("WALK-IN RATE")).to eq("walk_in")
  end

  it "leaves names the matcher never recognised as custom" do
    expect(backfilled_kind("Corporate Negotiated Rate")).to eq("custom")
    expect(backfilled_kind("Non-Refundable Rate")).to eq("custom")
    expect(backfilled_kind("Walk-in Special")).to eq("custom")
    expect(backfilled_kind("Standard")).to eq("custom")
  end
end
