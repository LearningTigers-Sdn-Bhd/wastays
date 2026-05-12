# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoomBlock, type: :model do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }

  describe "validations" do
    it "is valid with valid attributes" do
      block = RoomBlock.new(
        hotel: hotel,
        room_type: room_type,
        room_number: "101",
        start_date: Date.current,
        end_date: Date.current + 1.day,
        block_type: "maintenance",
        reason: "Leaky faucet"
      )
      expect(block).to be_valid
    end

    it "is valid with a custom block type" do
      block = RoomBlock.new(
        hotel: hotel,
        room_type: room_type,
        room_number: "101",
        start_date: Date.current,
        end_date: Date.current + 1.day,
        block_type: "Some custom reason",
        reason: "Leaky faucet"
      )
      expect(block).to be_valid
    end

    it "is invalid without a block_type" do
      block = RoomBlock.new(block_type: nil)
      block.valid?
      expect(block.errors[:block_type]).to include("can't be blank")
    end
  end
end
