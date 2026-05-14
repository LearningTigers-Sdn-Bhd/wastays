# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Room Block Inventory Sync", type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101", "102", "103" ], quantity: 3) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }

  before do
    permission = Permission.find_by(slug: "manage_room_status") || create(:permission, slug: "manage_room_status")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "Automatic Inventory Sync" do
    it "decrements inventory quantity and updates available_room_numbers when a block is created" do
      # Initial inventory check (nothing exists yet)
      expect(RoomInventory.count).to eq(0)

      # Create a block for Room 101 for today
      post hotel_room_blocks_path(hotel), params: {
        room_block: {
          room_type_id: room_type.id,
          room_number: "101",
          start_date: Date.current,
          end_date: Date.current,
          block_type: "maintenance",
          reason: "Leaky faucet"
        }
      }

      inventory = RoomInventory.find_by(room_type: room_type, date: Date.current)
      expect(inventory).to be_present
      expect(inventory.quantity).to eq(2) # 3 total - 1 block
      expect(inventory.available_room_numbers).to match_array([ "102", "103" ])
    end

    it "restores inventory when a block is removed" do
      # Create block first
      block = create(:room_block, hotel: hotel, room_type: room_type, room_number: "101", start_date: Date.current, end_date: Date.current)

      # Manual trigger since factory doesn't trigger the service
      Rooms::SyncInventory.new(hotel: hotel, room_type: room_type, start_date: Date.current, end_date: Date.current).call

      inventory = RoomInventory.find_by(room_type: room_type, date: Date.current)
      expect(inventory.quantity).to eq(2)

      # Remove the block via the controller (which uses the service)
      delete hotel_room_block_path(hotel, block)

      inventory.reload
      expect(inventory.quantity).to eq(3)
      expect(inventory.available_room_numbers).to match_array([ "101", "102", "103" ])
    end

    it "correctly counts existing bookings in the new quantity" do
      # 1. Create a booking for Room 102
      booking = create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day, status: "confirmed")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "102", quantity: 1)

      # 2. Create a block for Room 101
      post hotel_room_blocks_path(hotel), params: {
        room_block: {
          room_type_id: room_type.id,
          room_number: "101",
          start_date: Date.current,
          end_date: Date.current,
          block_type: "maintenance",
          reason: "Leaky faucet"
        }
      }

      inventory = RoomInventory.find_by(room_type: room_type, date: Date.current)
      # 3 total rooms
      # - 1 block (101)
      # - 1 booking (102)
      # = 1 sellable room remaining
      expect(inventory.quantity).to eq(1)
      expect(inventory.available_room_numbers).to match_array([ "102", "103" ]) # 102 is still 'sellable' physically but occupied
    end
  end
end
