# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::ImportPlan do
  describe ".normalize_agency" do
    it "collapses the spellings one agency is written with in the export" do
      canonical = described_class.normalize_agency("AMAZING BORNEO TOURS & EVENTS SDN BHD")

      # A double space, which HTML renders identically to a single one.
      expect(described_class.normalize_agency("AMAZING BORNEO TOURS & EVENTS  SDN BHD")).to eq(canonical)
      # Staff mark state by editing the name itself. Unstripped, these create a
      # second account for one agency and detach its bookings from the ledger.
      expect(described_class.normalize_agency("POSTPONE AMAZING BORNEO TOURS & EVENTS SDN BHD")).to eq(canonical)
      expect(described_class.normalize_agency("POSTPONED-AMAZING BORNEO TOURS & EVENTS SDN BHD")).to eq(canonical)
      # Punctuation on the company suffix varies row to row.
      expect(described_class.normalize_agency("AMAZING BORNEO TOURS & EVENTS SDN.BHD.")).to eq(canonical)
    end

    it "collapses a name the operator typed into the field twice" do
      expect(described_class.normalize_agency("BORNEO BIRDING TOURS SDN BHD BORNEO BIRDING TOURS SDN BHD"))
        .to eq(described_class.normalize_agency("BORNEO BIRDING TOURS SDN BHD"))
    end

    it "keeps genuinely different agencies apart" do
      # A typo, not a spelling variant. No rule should merge these -- only a
      # person can decide they are one agency.
      expect(described_class.normalize_agency("INTERPID TRAVEL (MALAYSIA) SDN BHD"))
        .not_to eq(described_class.normalize_agency("INTREPID TRAVEL (MALAYSIA) SDN BHD"))

      expect(described_class.normalize_agency("HAPPY TRAILS BORNEO TOURS SDN BHD"))
        .not_to eq(described_class.normalize_agency("HAPPY TRAILS MALAYSIA TOURS"))
    end
  end

  describe Ezee::ImportPlan::AgencyCollision do
    it "flags the spellings that differ only in whitespace" do
      collision = described_class.new(spellings: [
        "AMAZING BORNEO TOURS & EVENTS  SDN BHD",
        "AMAZING BORNEO TOURS & EVENTS SDN BHD",
        "POSTPONE AMAZING BORNEO TOURS & EVENTS SDN BHD"
      ])

      # These two render identically in HTML, so the page has to say why it is
      # listing what looks like the same name twice.
      expect(collision.whitespace_only?("AMAZING BORNEO TOURS & EVENTS  SDN BHD")).to be(true)
      expect(collision.whitespace_only?("AMAZING BORNEO TOURS & EVENTS SDN BHD")).to be(true)
      expect(collision.whitespace_only?("POSTPONE AMAZING BORNEO TOURS & EVENTS SDN BHD")).to be(false)
    end
  end
end
