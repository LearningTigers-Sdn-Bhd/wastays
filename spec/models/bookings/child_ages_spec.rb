# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ChildAges do
  describe ".normalize" do
    it "keeps one age per child, from an array or a typed list" do
      expect(described_class.normalize([ "8", 14 ], 2)).to eq([ 8, 14 ])
      expect(described_class.normalize("8, 14", 2)).to eq([ 8, 14 ])
    end

    it "drops the ages when their count does not match the children" do
      expect(described_class.normalize([ 8 ], 2)).to eq([])
      expect(described_class.normalize([ 8, "" ], 2)).to eq([])
      expect(described_class.normalize(nil, 1)).to eq([])
    end

    it "drops the ages when any of them is not a number" do
      expect(described_class.normalize([ "8", "ten" ], 2)).to eq([])
    end

    it "clamps an age into the range age bands cover" do
      expect(described_class.normalize([ 25 ], 1)).to eq([ RatePlanAgeBand::AGE_RANGE.max ])
    end

    it "is empty for no children" do
      expect(described_class.normalize([], 0)).to eq([])
    end
  end
end
