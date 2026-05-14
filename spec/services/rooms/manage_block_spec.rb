# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::ManageBlock, type: :service do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ], quantity: 1) }
  let(:user) { create(:user) }
  let(:params) do
    {
      room_type_id: room_type.id,
      room_number: "101",
      start_date: Date.current,
      end_date: Date.current + 1.day,
      block_type: "maintenance",
      reason: "Leaky faucet"
    }
  end

  subject { described_class.new(hotel: hotel, user: user, params: params) }

  describe "#create" do
    it "creates a room block and syncs inventory" do
      expect { subject.create }.to change(RoomBlock, :count).by(1)

      inventory = RoomInventory.find_by(room_type: room_type, date: Date.current)
      expect(inventory.quantity).to eq(0)
    end
  end

  describe "#finish" do
    let!(:block) { create(:room_block, hotel: hotel, room_type: room_type, room_number: "101", start_date: Date.current, end_date: Date.current + 1.day) }
    subject { described_class.new(hotel: hotel, user: user, block: block) }

    it "marks the block as completed and restores inventory" do
      # Initial sync (manual because factory)
      Rooms::SyncInventory.new(hotel: hotel, room_type: room_type, start_date: Date.current, end_date: Date.current + 1.day).call
      expect(RoomInventory.find_by(date: Date.current).quantity).to eq(0)

      subject.finish

      expect(block.reload.completed_at).to be_present
      expect(RoomInventory.find_by(date: Date.current).quantity).to eq(1)
    end
  end

  describe "#destroy" do
    let!(:block) { create(:room_block, hotel: hotel, room_type: room_type, room_number: "101", start_date: Date.current, end_date: Date.current + 1.day) }
    subject { described_class.new(hotel: hotel, user: user, block: block) }

    it "destroys the block and restores inventory" do
      # Initial sync
      Rooms::SyncInventory.new(hotel: hotel, room_type: room_type, start_date: Date.current, end_date: Date.current + 1.day).call

      expect { subject.destroy }.to change(RoomBlock, :count).by(-1)
      expect(RoomInventory.find_by(date: Date.current).quantity).to eq(1)
    end
  end
end
