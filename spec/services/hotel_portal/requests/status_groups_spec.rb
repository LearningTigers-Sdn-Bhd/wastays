# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Requests::StatusGroups do
  describe ".statuses_for" do
    # "Pending" is the group of work nobody has finished, not the literal
    # status. A request taken by a dispatcher reads "new" and is still owed.
    it "counts dispatched work as pending" do
      statuses = described_class.statuses_for(kind: "housekeeping", group: "pending")

      expect(statuses).to include("pending", "new", "assigned", "in_progress")
    end

    it "reads a checkout's own vocabulary for the same group" do
      expect(described_class.statuses_for(kind: "checkout", group: "pending"))
        .to eq(CheckOutRequest::OPEN_STATUSES)
    end

    # A complaint is resolved where housekeeping is completed, and the group has
    # to find both.
    it "gathers the two spellings of finished" do
      expect(described_class.statuses_for(kind: "housekeeping", group: "completed"))
        .to contain_exactly("completed", "resolved")
    end

    it "narrows nothing for a blank filter, for all, and for a group it does not know" do
      [ nil, "", "all", "invented" ].each do |group|
        expect(described_class.statuses_for(kind: "housekeeping", group: group))
          .to be_nil, "expected #{group.inspect} to narrow nothing"
      end
    end
  end

  describe ".match?" do
    it "keeps everything when the filter asks for nothing" do
      [ nil, "", "all", "invented" ].each do |group|
        expect(described_class.match?(group, "completed")).to be(true)
      end
    end

    it "answers whether a status belongs to the group" do
      expect(described_class.match?("pending", "in_progress")).to be(true)
      expect(described_class.match?("pending", "completed")).to be(false)
    end
  end

  describe ".aliases_for" do
    # Typing "pend" has to find work that now reads "new".
    it "reaches the whole group from a partly typed group name" do
      expect(described_class.aliases_for("pend")).to include("new", "assigned", "in_progress")
    end

    it "reaches the group from a partly typed status inside it" do
      expect(described_class.aliases_for("resolv")).to include("completed", "resolved")
    end

    it "offers nothing for a blank term or a term naming no status" do
      expect(described_class.aliases_for("")).to eq([])
      expect(described_class.aliases_for("   ")).to eq([])
      expect(described_class.aliases_for("zzz")).to eq([])
    end
  end
end
