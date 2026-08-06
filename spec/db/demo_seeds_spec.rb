# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/demo_seeds")

RSpec.describe DemoSeeds do
  describe ".room_numbers_for" do
    it "generates quantity-matched room numbers on the room type floor" do
      expect(described_class.room_numbers_for(0, 3)).to eq(%w[101 102 103])
      expect(described_class.room_numbers_for(2, 2)).to eq(%w[301 302])
    end

    it "does not overlap room numbers between room types" do
      first_floor = described_class.room_numbers_for(0, 16)
      second_floor = described_class.room_numbers_for(1, 6)

      expect(first_floor & second_floor).to be_empty
    end

    it "returns no room numbers for zero quantity" do
      expect(described_class.room_numbers_for(0, 0)).to be_empty
    end
  end
end
